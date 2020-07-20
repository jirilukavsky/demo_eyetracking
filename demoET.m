function demoET(id)
    % vse co se napise na obrazovku, ulozi se do logu
    diary('./logs/log.txt'); % Eyelink '.'
    DisplayHeader('demoET');
       
    % zakladni udaje o obrazovce a experimentu do promenne info
    info = SetupInfo(); 
    info.viewingDistance = 500;
    info = SetupWindow(info);  
    
    % zkratky pro kody barev
    black = [0 0 0]; white = [255 255 255]; 
    red = [255 0 0]; green = [0 255 0]; blue = [0 0 255]; yellow = [255 255 0];
    midGray = [128 128 128]; darkGray = [64 64 64]; lightGray = [192 192 192];
    defaultFont = 'Dejavu Sans'; % nebo 'Arial' 

    % do info doplnime dalsi udaje, specificke pro nas experiment
    info.id           = id;
    info.textColor    = black;
    info.edfFile      = sprintf('r%04d.edf',info.id); % pozor max. 8 znaku
    info.version      = version;
    info.eyelink      = 1; % ET: 1 = chceme merit ocni pohyby
    info.dummyMode    = 0; % ET: 0 = skutecne mereni, 1 = dummy mode
    
    % vsechna nastaveni zobrazime, ulozi se tim do logu
    display(info);

    % ET: nez spustime eyetracking, overime, ze sit funguje
    if info.eyelink
        fprintf('* Connecting to Eyelink...');
        noResponse = unix('ping 100.1.1.1 -c 5 -W 2 >> ./logs/log.txt');
        if noResponse
            fprintf('\n  * Could not reach the eye tracker. Check the network setting or cable.\n\nExiting.\n');
            sca; cleanup;
            return % skoncime nyni
        else
            fprintf('OK\n');
        end
    end
    
    % nacteme jednotlive obrazky
    slideCount = 4;
    slideFile = cell(slideCount, 1);
    slideTexture = cell(slideCount, 1);
    slideDriftCorrect = ones(slideCount, 1); 
    for i = 1:slideCount
        slideFile{i} = sprintf('images/image_%03d.jpg', i);
        img = imread(slideFile{i});
        slideTexture{i} = Screen('MakeTexture', info.window, img);        
    end
    info.slideSize = [0 0 1024 1024]; %Screen('Rect', slideTexture{1})        
    info.slideDestRect = CenterRect(info.slideSize, info.screenRect);
    
    % zacina experiment
    try
        % ET: zakladni nastaveni eyetrackeru
        if info.eyelink
            % ET: pripojime se k eyetrackeru 
            el = EyelinkInitDefaults(info.window);
            if ~EyelinkInit(info.dummyMode)
                fprintf('* Eyelink Init aborted.\n');
                cleanup; return
            end
            [v vs] = Eyelink('GetTrackerVersion');
            fprintf('* Running experiment on a ''%s'' tracker.\n', vs);

            % ET: nastavime kam ukladat data
            i = Eyelink('OpenFile', info.edfFile);
            if i ~= 0
                fprintf('Cannot create EDF file ''%s''\n', info.edfFile);
                cleanup; return;
            end
            fprintf('Eyelink connected, EDF file ''%s'' created.\n', info.edfFile);
            Eyelink('command','add_file_preamble_text ''Recorded by demo''');
            
            % ET: nastavime zakladni promenne, vizualni podoba kalibrace
            el.backgroundcolour = GrayIndex(el.window); 
            el.foregroundcolour = BlackIndex(el.window);
            el.msgfontcolour    = BlackIndex(el.window);
            el.imgtitlecolour   = BlackIndex(el.window);
            el.msgfont          = defaultFont;
            el.msgfontsize      = 16;
            el.imgtitlefont     = defaultFont;
            el.imgtitlefontsize = 16;
            el.calibrationtargetcolour = [0 0 0]; 
            PsychEyelinkDispatchCallback(el);
        end
        
        % cyklus prezentace obrazku
        for slide = 1:slideCount
            
            % ET: pokud je to prvni obrazek, spustime kalibraci eyetrackeru
            if (slide == 1) && info.eyelink 
                EyelinkDoTrackerSetup(el);
            end                
                
            % ET: drift korekce
            if info.eyelink
                msg = sprintf('TRIALID %d', slide);
                Eyelink('Message', msg);
                msg = sprintf('VERSION %s', info.version);
                Eyelink('Message', msg);
                if slideDriftCorrect(slide)
                    EyelinkDoDriftCorrection(el);
                end
            end            
            
            % ET: zahajime nahravani dat
            SetPriority(info,1); % zvysime prioritu pro lepsi vykon
            if info.eyelink
                Eyelink('StartRecording');
                WaitSecs(0.1);   % doporucuje se chvili pockat, nez se nahravani rozjede
            end
            
            % namalujeme obrazek a cekame
            Screen('DrawTexture', info.window, slideTexture{slide}, [], info.slideDestRect);
            Screen('Flip', info.window);
            Eyelink('Message', 'SYNCTIME'); % ET: znacka do zaznamu, ze jsme ukazali obrazek 
            WaitSecs(5); 
            
            % ET: ukoncime nahravani
            if info.eyelink 
                WaitSecs(0.1);    % opet chvili pockame
                Eyelink('StopRecording');
            end            
            SetPriority(info,0);  % vratime prioritu
            
        end
        
        % vse je odprezentovano, jdeme data ulozit k nam na disk
        if info.eyelink
            Message(info, 'Dekujeme za ucast', black, 1, ...
                'Chvili strpeni, ukladam data');
            % ET: ukoncime zaznam, dalsi data nechceme ukladat
            Eyelink('Command', 'set_idle_mode');
            WaitSecs(0.5);
            Eyelink('CloseFile');
            % ET: stahneme EDF soubor z eyetrackeru na nas disk
            try
                fprintf('* Receiving data file ''%s''...\n', info.edfFile);
                status = Eyelink('ReceiveFile');
                if status > 0
                    fprintf('* ReceiveFile status = %d\n', status);
                end
                if exist(info.edfFile, 'file') == 2
                    fprintf('* Data file ''%s'' can be found in ''%s''\n', ...
                        info.edfFile, pwd);
                end
            catch MEE
                fprintf('* Problem receiving data file ''%s''\n', info.edfFile);
            end
            cleanup
        end
    
    catch ME
        % pokud dojde k problemu
        cleanup();
        rethrow(ME);
    end
    % ET: vypneme eyetracker, zavreme okno, vypneme logovani, zapneme mys
    cleanup();
end


%% pomocne fuknce -----------------------------------------------
% krome cleanup neobsahuje funkce specificke pro eyetracking experimenty
% v cleanup volame Eyelink('Shutdown') pro odpojení eyetrackeru
% ---------------------------------------------------------------

%% cleanup - vse co je potreba udelat na konci experimentu
function cleanup()
    Eyelink('Shutdown');
    Screen('CloseAll');
    ShowCursor;
    diary off;
end

%% DisplayHeader - hlavicka s nazvem experimentu, ktera se zapise do logu
function DisplayHeader(expname)
    disp(repmat('*',1,80));
    fprintf('Experiment %s   ', expname);
    disp(datestr(now)); disp(repmat('*',1,80));
end

%% Message - ukaze text na obrazovce
function Message(info, feedbackMsg, color, seconds, subtitle)
    if nargin < 5, subtitle = ''; end;
    Screen('TextSize', info.window, 36);
    DrawFormattedText(info.window, feedbackMsg, ...
        'center', 'center', color, 80);
    if ~isempty(subtitle)
        Screen('TextSize', info.window, 20);
        DrawFormattedText(info.window, subtitle, ...
            'center', info.screenCenter(2)*1.1, color, 80);
    end
    Screen('Flip', info.window);
    if seconds > 0
        WaitSecs(seconds);
    else
        WaitMouse(info.window);
    end
end

%% SetupInfo - nastavi vychozi/prazdne hodnoty pro experiment
function p=SetupInfo
    p = {};
    p.window = [];
    p.viewingDistance = []; % mm
    p.fps = [];
    p.screenRect = [];
    p.screenSize = [];
    p.screenCenter = [];
    p.pixelsPerDegree = [];
    p.backgroundColor = [0 0 0];
    p.screenNumber = [];
    p.maxPriority = [];
    p.usePriority = true;
end

%% SetupWindow - otevre okno a zjisti o nem zakladni informace
function ui=SetupWindow(info)
    ui = info; % ui = updated info

    ui.screenNumber = max(Screen('Screens'));
    [monitorXmm, monitorYmm] = Screen('DisplaySize', ui.screenNumber);
    ui.screenSize = [monitorXmm monitorYmm];
    ui.screenRect = Screen('Rect', ui.screenNumber);
    [srx sry] = RectCenter(ui.screenRect);
    ui.screenCenter = [srx sry];
    diagonalMm = sqrt(monitorXmm^2 + monitorYmm^2); % diagonal length in mm
    diagonalPixels = sqrt(sum(ui.screenRect.^2));
    ui.pixelsPerDegree = PixelSize(1, ui.viewingDistance, diagonalPixels, diagonalMm);
    
    try
        % open windows
        % basic setup
        AssertOpenGL;
        InitializeMatlabOpenGL;
        Screen('Preference', 'SkipSyncTests', 0);
        Screen('Preference', 'VisualDebugLevel', 3);
        ui.window = Screen('OpenWindow', ui.screenNumber, ui.backgroundColor);
        Screen('BlendFunction', ui.window, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        
        ui.maxPriority = MaxPriority(ui.window); 
        Priority(ui.maxPriority);  % enable realtime scheduling
        
        interFrameInterval = Screen('GetFlipInterval', ui.window); % get refresh interval
        ui.fps = 1/interFrameInterval;
        
        Priority(0); 
        pointSizeRange = glGetIntegerv(GL.SMOOTH_POINT_SIZE_RANGE);
        HideCursor;
    catch ME
        ME.rethrow;
    end
    ui = TimeSetup(ui);
end


%% SetPriority - pokud chceme nastavovat prioritu programu, tak ji nastavi
function SetPriority(info, on) 
    if (info.usePriority)
        if (on)
            Priority(info.maxPriority);
        else
            Priority(0);  
        end
    end
end

%% PixelSize - prepocet uhlove velikosti na pixely
function pixSize = PixelSize( degSize, viewDistance, screenResolution, monitorSize )
% function pixSize = 
%     PixelSize( degSize, viewDistance, screenResolution, monitorSize )
%
%   Function for calculating of object size in pixels based on their
%   planned size in degrees of visual field.
%
%   degSize          - size in degrees (1 or 2 dim)
%   viewDistance     - viewing distance in cm
%   screenResolution - resolution in pixels (1 or 2 dim)
%   monitorSize      - screen size in cm (or same units as viewDistance)
%
%   Returns size in pixels (2 dim if 2 dim screenResolution provided, 
%       same dim as degSize otherwise)

    radSize = degSize ./ 180 .* pi;
    cmSize  = 2 .* viewDistance .* tan(radSize ./ 2);
    pixSize = cmSize ./ monitorSize .* screenResolution;
end

%% TimeSetup - nastavi vychozi casovou znacku
function i=TimeSetup(info)
    i = info;
    i.setupTime = GetSecs()*1.0e6;    
end

%% TimeStamp - zmeri cas od casove znacky
function t=TimeStamp(info)
    now = GetSecs()*1.0e6;
    t   = now - info.setupTime;
end
