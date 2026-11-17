package com.exadel.frs.service;

import com.exadel.frs.commonservice.repository.ImgRepository;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.UUID;
import javax.persistence.EntityManager;
import javax.persistence.PersistenceContext;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

/**
 * Security fix (audit MFC-07): deleting a model or an application cascades in the database to subjects and
 * embeddings, but never to the {@code img} table (only {@code embedding.img_id} references it). Without this
 * cleanup every enrolled face photo of a deleted model stayed in the database and its backups.
 *
 * <p>Usage inside the deleting transaction: collect the image ids first, delete the model/app, then call
 * {@link #deleteUnreferenced(Collection)}.
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class ModelImageCleaner {

    private final ImgRepository imgRepository;

    @PersistenceContext
    private EntityManager entityManager;

    public List<UUID> collectImageIds(final Collection<String> modelApiKeys) {
        List<UUID> ids = new ArrayList<>();
        for (String apiKey : modelApiKeys) {
            if (apiKey != null) {
                ids.addAll(imgRepository.findImgIdsBySubjectApiKey(apiKey));
            }
        }
        return ids;
    }

    public void deleteUnreferenced(final Collection<UUID> imageIds) {
        if (imageIds == null || imageIds.isEmpty()) {
            return;
        }
        // make sure the model/app delete (and its DB cascade to subject/embedding) has been executed
        entityManager.flush();
        int deleted = imgRepository.deleteUnreferencedByIds(imageIds);
        log.info("Removed {} face image(s) of deleted model(s)", deleted);
    }
}
