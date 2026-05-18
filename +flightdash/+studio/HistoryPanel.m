classdef HistoryPanel < handle
    % flightdash.studio.HistoryPanel
    % Displays the undo/redo history for the active Studio session.

    properties
        Parent
        Grid
        ListBox
        UndoService = []
        Listener = []
    end

    methods
        function obj = HistoryPanel(parent, undoService)
            obj.Parent = parent;
            obj.build(parent);
            if nargin >= 2
                obj.bindUndoService(undoService);
            else
                obj.refresh();
            end
        end

        function delete(obj)
            try
                if ~isempty(obj.Listener) && isvalid(obj.Listener)
                    delete(obj.Listener);
                end
            catch
            end
            obj.Listener = [];
        end

        function bindUndoService(obj, undoService)
            try
                if ~isempty(obj.Listener) && isvalid(obj.Listener)
                    delete(obj.Listener);
                end
            catch
            end
            obj.Listener = [];
            obj.UndoService = undoService;
            try
                if ~isempty(undoService) && isvalid(undoService)
                    obj.Listener = addlistener(undoService, 'StateChanged', @(~,~) obj.refresh());
                end
            catch
                obj.Listener = [];
            end
            obj.refresh();
        end

        function refresh(obj)
            try
                if isempty(obj.ListBox) || ~isvalid(obj.ListBox), return; end
                if isempty(obj.UndoService) || ~isvalid(obj.UndoService)
                    obj.ListBox.Items = {'작업 이력이 없습니다'};
                    obj.ListBox.Value = '작업 이력이 없습니다';
                    return;
                end

                items = {};
                undoStack = obj.UndoService.UndoStack;
                redoStack = obj.UndoService.RedoStack;

                for i = 1:numel(undoStack)
                    items{end+1} = sprintf('Undo: %s', obj.commandDescription(undoStack{i})); %#ok<AGROW>
                end
                for i = numel(redoStack):-1:1
                    items{end+1} = sprintf('Redo: %s', obj.commandDescription(redoStack{i})); %#ok<AGROW>
                end

                if isempty(items)
                    items = {'작업 이력이 없습니다'};
                end
                obj.ListBox.Items = items;
                obj.ListBox.Value = items{end};
            catch
            end
        end
    end

    methods (Access = private)
        function build(obj, parent)
            obj.Grid = uigridlayout(parent, [1 1], 'Padding', [4 4 4 4]);
            obj.ListBox = uilistbox(obj.Grid, 'Items', {'작업 이력이 없습니다'});
        end

        function desc = commandDescription(~, command)
            desc = 'Command';
            try
                if ~isempty(command) && isprop(command, 'Description') && ~isempty(command.Description)
                    desc = char(command.Description);
                end
            catch
                desc = 'Command';
            end
        end
    end
end
