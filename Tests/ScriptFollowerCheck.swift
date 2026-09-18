import Foundation

@main
struct ScriptFollowerCheck {
    static func main() {
        var follower = ScriptFollower()
        follower.load("Hola mundo. Esta es una prueba sencilla. Ahora hacemos una pausa. Final.")
        precondition(follower.follow("Hola") == 1)
        precondition(follower.follow("Hola mundo") == 2)
        precondition(follower.follow("Hola mundo esta es una prueba") == 6)
        precondition(follower.follow("Hola mundo esta es una prueba") == 6, "Repeated partial results must not move")
        precondition(follower.follow("una pausa") == 11, "A short skip should recover")
        precondition(follower.follow("cualquier cosa") == 11, "Off-script speech must wait")
        follower.seek(to: 2)
        precondition(follower.follow("esta es una") == 5)
        follower.load("Canción, acción; mañana.")
        precondition(follower.follow("cancion accion manana") == 3, "Accents must be optional")
        let marked = "Hola—mundo, buenos días."
        precondition(ScriptFollower.displayWords(in: marked).count == ScriptFollower.words(in: marked).count)
        follower.load("Hello everyone. Today we are recording a short video together.")
        precondition(follower.follow("Hello everyone") == 2, "English speech must advance")
        precondition(follower.follow("Hello everyone today we are recording") == 6)
        precondition(follower.follow("Hello everyone today we are recording") == 6, "Partial results must not repeat words")
        print("ScriptFollower: 12 checks passed")
    }
}
