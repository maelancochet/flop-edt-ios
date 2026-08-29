import Testing

/// Suite parente des tests qui passent par ``StubURLProtocol``.
///
/// `StubURLProtocol` configure `URLSession` par des variables statiques, donc
/// partagées par tout le processus. Le trait `.serialized` ne sérialise qu'à
/// l'intérieur d'une suite : deux suites sœurs tourneraient en parallèle et se
/// videraient mutuellement leurs bouchons. Les imbriquer ici les met sous une
/// même sérialisation.
@Suite("Réseau simulé", .serialized)
struct StubbedNetwork {}
