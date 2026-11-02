import 'package:flutter/material.dart';
import 'main.dart';

Widget construirInterfazPrincipal(
    BuildContext context, _TvaHomeScreenState estado) {
  return OrientationBuilder(
    builder: (context, orientation) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      bool esHorizontal = orientation == Orientation.landscape;
      final double playerHeight = MediaQuery.of(context).size.width * (9 / 16);

      if (esHorizontal && estado._mostrarPlayer) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: estado._isPlayerInitialized
                  ? VideoPlayer(estado._videoController)
                  : const Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white10)),
            ),
          ),
        );
      }

      return Scaffold(
        backgroundColor: Colors.black,
        body: CustomScrollView(
          controller: estado._scrollController,
          slivers: [
            SliverAppBar(
              backgroundColor: Colors.black,
              centerTitle: true,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (estado._mostrarPlayer)
                    GestureDetector(
                      onTap: () => estado._scrollController.animateTo(0.0,
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.easeInOut),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Icon(Icons.tv, size: 16, color: Colors.white24),
                      ),
                    ),
                  const Text('CANAL 9 TVA',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 1.2)),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.cloud_upload_outlined,
                      color: Colors.blueAccent, size: 22),
                  onPressed: estado._gestionarSubidaMaterial,
                ),
                if (estado._mostrarPlayer)
                  IconButton(
                      icon: const Icon(Icons.cast_connected,
                          color: Colors.white, size: 20),
                      onPressed: estado._iniciarBusquedaAutomatica),
              ],
              pinned: true,
              floating: false,
            ),
            if (estado._mostrarPlayer)
              SliverAppBar(
                backgroundColor: Colors.black,
                automaticallyImplyLeading: false,
                expandedHeight: playerHeight,
                collapsedHeight: playerHeight,
                toolbarHeight: playerHeight,
                pinned: estado._isPinned,
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      estado._isPlayerInitialized
                          ? VideoPlayer(estado._videoController)
                          : const Center(
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white10)),
                      Positioned(
                        top: 5,
                        right: 5,
                        child: GestureDetector(
                          onTap: estado._togglePin,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.5),
                                shape: BoxShape.circle),
                            child: Icon(
                              estado._isPinned
                                  ? Icons.push_pin
                                  : Icons.push_pin_outlined,
                              color: estado._isPinned
                                  ? Colors.blueAccent
                                  : Colors.white54,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(15, 20, 10, 10),
                child: Text("CRÓNICAS REALES",
                    style: TextStyle(
                        color: Colors.white30,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5)),
              ),
            ),
            if (estado._isNoticiasLoading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(40.0),
                  child: Center(
                      child: CircularProgressIndicator(color: Colors.white24)),
                ),
              )
            else if (estado.noticiasReales.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(40.0),
                  child: Center(
                      child: Text("No hay noticias disponibles en este momento",
                          style: TextStyle(color: Colors.white38))),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    return GestureDetector(
                      onTap: () {
                        if (estado._mostrarPlayer &&
                            estado._isPlayerInitialized) {
                          estado._videoController.pause();
                        }
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => NoticiaDetalleScreen(
                                  noticia: estado.noticiasReales[i])),
                        ).then((_) {
                          if (estado._mostrarPlayer) {
                            estado._reengancharVideo();
                          }
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 2.0),
                        decoration:
                            const BoxDecoration(color: Color(0xFF0F0F0F)),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 6,
                              child: AspectRatio(
                                aspectRatio: 16 / 9,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.network(
                                      estado.noticiasReales[i]['imagen'] ??
                                          'https://picsum.photos/400/300',
                                      fit: BoxFit.cover,
                                      errorBuilder: (c, e, s) => Container(
                                          color: Colors.white10,
                                          child: const Icon(Icons.newspaper,
                                              color: Colors.white24, size: 24)),
                                    ),
                                    Positioned(
                                      bottom: 0,
                                      left: 0,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        color:
                                            Colors.blueAccent.withOpacity(0.9),
                                        child: Text(
                                            estado.noticiasReales[i]
                                                    ['categoria'] ??
                                                'INFO',
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 6.5,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: 0.5)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 4,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        estado.noticiasReales[i]['fecha'] ?? '',
                                        style: const TextStyle(
                                            color: Colors.white38,
                                            fontSize: 6.0,
                                            fontWeight: FontWeight.normal)),
                                    const SizedBox(height: 3),
                                    Text(
                                        estado.noticiasReales[i]['titulo'] ??
                                            'Sin título',
                                        maxLines: 2,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 7.5,
                                            fontWeight: FontWeight.w600,
                                            height: 1.1)),
                                    const SizedBox(height: 3),
                                    Text(
                                        estado.noticiasReales[i]
                                                ['descripcion'] ??
                                            '',
                                        maxLines: 3,
                                        textAlign: TextAlign.justify,
                                        style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 6.0,
                                            fontWeight: FontWeight.normal,
                                            height: 1.1)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: estado.noticiasReales.length,
                ),
              ),
            SliverToBoxAdapter(
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    height: 40,
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    decoration: const BoxDecoration(
                        color: Color(0xFF0A0A0A),
                        border: Border.symmetric(
                            horizontal:
                                BorderSide(color: Colors.white10, width: 0.5))),
                    child: const Center(
                        child: Text("AVRORA SOFT - VIBOLA LLC | PUBLICIDAD",
                            style: TextStyle(
                                color: Colors.white10,
                                fontSize: 7,
                                letterSpacing: 1.5))),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 20),
                    child: Center(
                        child: Text('Avrora Soft - Vibola LLC',
                            style: TextStyle(
                                color: Colors.white24,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0))),
                  ),
                ],
              ),
            )
          ],
        ),
      );
    },
  );
}
