import math

class DetectedObject:
    def __init__(self, obj_id, class_name, box, confidence):
        self.obj_id = obj_id
        self.class_name = class_name
        self.box = box  # [ymin, xmin, ymax, xmax] normalized
        self.confidence = confidence
        self.area = (box[2] - box[0]) * (box[3] - box[1])
        self.center = ((box[1] + box[3]) / 2, (box[0] + box[2]) / 2)

class ObjectTracker:
    def __init__(self):
        self.tracked_objects = {}  # {obj_id: [history_of_areas]}
        self.next_id = 0
        self.max_history = 5

    def update(self, current_objects):
        # Extremely simple centroid tracking for demonstration
        updated_tracks = {}
        for obj in current_objects:
            best_id = None
            min_dist = float('inf')
            
            for t_id, history in self.tracked_objects.items():
                if not history: continue
                last_obj = history[-1]['obj']
                # Calculate distance between centers
                dist = math.hypot(obj.center[0] - last_obj.center[0], obj.center[1] - last_obj.center[1])
                
                if dist < 0.2 and dist < min_dist: # Normalized distance threshold
                    min_dist = dist
                    best_id = t_id

            if best_id is None:
                best_id = self.next_id
                self.next_id += 1
                updated_tracks[best_id] = []
            else:
                updated_tracks[best_id] = self.tracked_objects[best_id]
                # Remove from old so it can't be matched twice
                del self.tracked_objects[best_id]

            obj.obj_id = best_id
            updated_tracks[best_id].append({'obj': obj, 'area': obj.area})
            if len(updated_tracks[best_id]) > self.max_history:
                updated_tracks[best_id].pop(0)

        self.tracked_objects = updated_tracks
        return current_objects

    def is_closing_in(self, obj_id):
        if obj_id not in self.tracked_objects:
            return False
        history = self.tracked_objects[obj_id]
        if len(history) < 3:
            return False
        
        # If the area is consistently increasing, it is getting closer
        start_area = history[0]['area']
        end_area = history[-1]['area']
        
        if end_area > start_area * 1.1: # 10% increase in area over tracking window
            return True
        return False

def calculate_normalized_distance(box):
    # Very simple pinhole camera inverse height/area approximation
    # 0.0 means right on our bumper, 1.0 means far horizon
    area = (box[2] - box[0]) * (box[3] - box[1])
    
    # Assuming max area an object can take up before collision is 0.8 of the screen
    clamped_area = min(area, 0.8)
    
    # Invert so larger area = smaller distance
    distance = 1.0 - (clamped_area / 0.8)
    return max(0.0, min(1.0, distance))
