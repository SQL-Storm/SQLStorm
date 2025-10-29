-- {"query": "1941.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2624}
WITH TagFilteredPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        p.LastActivityDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.AcceptedAnswerId,
        p.ClosedDate,
        LOWER(p.Body) AS PostBodyLower,
        p.Tags,
        p.Body AS CurrentRawBody,
        -- normalize tags: remove leading/trailing angle brackets then split by '><'
        -- use standard SQL: replace leading '<' and trailing '>' if present, then split by '><'
        -- Many SQL dialects use SPLIT or STRING_SPLIT; use a portable approach assuming a function SPLIT_PART_ARRAY or regexp_split_to_array may not exist.
        -- For compatibility, produce as comma-separated list by replacing '><' with ',' and trimming angle brackets, then later treat by searching with LIKE on the text.
        REPLACE(SUBSTR(p.Tags, 2, CAST(LENGTH(p.Tags) - 2 AS INTEGER)), '><', ',') AS TagArrayText
    FROM Posts p
    WHERE
        p.PostTypeId = 1
        AND (
            LOWER(p.Title) LIKE '%performance%' OR LOWER(p.Title) LIKE '%optimization%' OR LOWER(p.Title) LIKE '%benchmark%'
            OR p.Tags LIKE '%<performance>%' OR p.Tags LIKE '%<optimization>%' OR p.Tags LIKE '%<benchmark>%'
        )
        AND p.CreationDate >= DATE '2020-01-01'
),
PostHistoryDetails AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate AS HistoryEventDate,
        ph.Text AS HistoryTextContent,
        ph.Comment AS HistoryCommentValue,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn_latest_event,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) as rn_latest_of_type
    FROM PostHistory ph
    WHERE ph.PostId IN (SELECT PostId FROM TagFilteredPosts)
      AND ph.PostHistoryTypeId IN (2,5,8,10,11)
),
AggregatedPostHistory AS (
    SELECT
        phd.PostId,
        MAX(CASE WHEN phd.PostHistoryTypeId = 2 AND phd.rn_latest_of_type = 1 THEN phd.HistoryTextContent ELSE NULL END) AS InitialBodyContent,
        MAX(CASE WHEN phd.PostHistoryTypeId IN (5,8) AND phd.rn_latest_event = 1 THEN phd.HistoryTextContent ELSE NULL END) AS LatestEditBodyContent,
        COUNT(DISTINCT CASE WHEN phd.PostHistoryTypeId IN (5,8) THEN phd.HistoryEventDate ELSE NULL END) AS DistinctEditCount,
        MAX(CASE WHEN phd.PostHistoryTypeId = 10 AND phd.HistoryCommentValue IN ('101','1','2') THEN 1 ELSE 0 END) = 1 AS WasClosedAsDuplicateOrOffTopic,
        MAX(CASE WHEN phd.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) = 1 AS WasReopened,
        MIN(CASE WHEN phd.PostHistoryTypeId = 10 THEN phd.HistoryEventDate ELSE NULL END) AS FirstCloseDate,
        MAX(CASE WHEN phd.PostHistoryTypeId = 11 THEN phd.HistoryEventDate ELSE NULL END) AS LastReopenDate
    FROM PostHistoryDetails phd
    GROUP BY phd.PostId
)
SELECT
    tfp.PostId,
    tfp.Title,
    tfp.PostScore,
    tfp.ViewCount,
    tfp.AnswerCount,
    tfp.CommentCount,
    tfp.FavoriteCount,
    tfp.PostCreationDate,
    tfp.LastActivityDate,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    tfp.ClosedDate AS PostClosedDate,
    COALESCE(aph.WasClosedAsDuplicateOrOffTopic, FALSE) AS FlaggedClosedAsDuplicateOrOffTopic,
    COALESCE(aph.WasReopened, FALSE) AS FlaggedReopened,
    COALESCE(aph.DistinctEditCount, 0) AS TotalDistinctEdits,
    COALESCE(NULLIF(LENGTH(aph.LatestEditBodyContent), 0), LENGTH(tfp.CurrentRawBody)) AS FinalBodyLength,
    ABS(LENGTH(COALESCE(aph.InitialBodyContent, '')) - LENGTH(COALESCE(aph.LatestEditBodyContent, tfp.CurrentRawBody, ''))) AS BodyLengthChange,
    TRIM(SUBSTRING(tfp.Title FROM 1 FOR 75)) AS TitleExcerpt,
    SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS TotalBountyOffered,
    COUNT(DISTINCT c.Id) AS TotalCommentsReceived,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId ELSE NULL END) AS NumberOfDuplicateLinks,
    AVG(tfp.PostScore) OVER (PARTITION BY tfp.OwnerUserId) AS AvgPostScoreByOwner,
    RANK() OVER (ORDER BY tfp.PostScore DESC, tfp.ViewCount DESC, tfp.FavoriteCount DESC) AS GlobalPostEngagementRank,
    LAG(tfp.PostCreationDate, 1, TIMESTAMP '1970-01-01') OVER (PARTITION BY tfp.OwnerUserId ORDER BY tfp.PostCreationDate) AS PreviousPostCreationDateByOwner,
    CASE
        WHEN tfp.ClosedDate IS NOT NULL AND COALESCE(aph.WasClosedAsDuplicateOrOffTopic, FALSE) AND COALESCE(aph.WasReopened, FALSE) THEN 'Closed (Duplicate/Off-Topic) & Reopened'
        WHEN tfp.ClosedDate IS NOT NULL AND COALESCE(aph.WasClosedAsDuplicateOrOffTopic, FALSE) THEN 'Closed as Duplicate/Off-Topic'
        WHEN tfp.ClosedDate IS NOT NULL AND aph.FirstCloseDate IS NOT NULL THEN 'Closed (Other Reasons)'
        WHEN tfp.ClosedDate IS NULL AND COALESCE(aph.WasReopened, FALSE) THEN 'Reopened But Currently Open'
        ELSE 'Open and Active'
    END AS DetailedPostState,
    EXISTS (
        SELECT 1
        FROM Posts op_corr
        WHERE op_corr.OwnerUserId = tfp.OwnerUserId
          AND op_corr.PostTypeId = 1
          AND op_corr.Id != tfp.PostId
          AND op_corr.ViewCount > 75000
          AND op_corr.CreationDate BETWEEN tfp.PostCreationDate - INTERVAL '6 months' AND tfp.PostCreationDate + INTERVAL '6 months'
        LIMIT 1
    ) AS OwnerHasOtherHighViewQuestionNearTime,
    (SELECT COUNT(b.Id)
     FROM Badges b
     WHERE b.UserId = tfp.OwnerUserId
       AND b.TagBased = TRUE
       AND LOWER(b.Name) IN ('performance', 'optimization', 'benchmarking')
       AND b.Date >= tfp.PostCreationDate - INTERVAL '1 year' AND b.Date <= tfp.PostCreationDate + INTERVAL '6 months'
    ) AS RelevantTagBadgesCount,
    -- Count of specific tech tags by searching the TagArrayText string to avoid dialect-specific UNNEST behavior
    (
      (CASE WHEN LOWER(tfp.TagArrayText) LIKE 'c#,%' OR LOWER(tfp.TagArrayText) LIKE '%,c#,%' OR LOWER(tfp.TagArrayText) LIKE '%,c#' OR LOWER(tfp.TagArrayText) = 'c#' THEN 1 ELSE 0 END)
      +
      (CASE WHEN LOWER(tfp.TagArrayText) LIKE 'java,%' OR LOWER(tfp.TagArrayText) LIKE '%,java,%' OR LOWER(tfp.TagArrayText) LIKE '%,java' OR LOWER(tfp.TagArrayText) = 'java' THEN 1 ELSE 0 END)
      +
      (CASE WHEN LOWER(tfp.TagArrayText) LIKE 'python,%' OR LOWER(tfp.TagArrayText) LIKE '%,python,%' OR LOWER(tfp.TagArrayText) LIKE '%,python' OR LOWER(tfp.TagArrayText) = 'python' THEN 1 ELSE 0 END)
    ) AS SpecificTechTagCount,
    (u.Reputation * 0.05 + tfp.PostScore * 0.75 + tfp.ViewCount / 1500.0 + COALESCE(tfp.AnswerCount, 0) * 1.5 + COALESCE(tfp.FavoriteCount, 0) * 1.0) AS WeightedEngagementScore
FROM TagFilteredPosts tfp
LEFT JOIN Users u ON tfp.OwnerUserId = u.Id
LEFT JOIN AggregatedPostHistory aph ON tfp.PostId = aph.PostId
LEFT JOIN Votes v ON tfp.PostId = v.PostId
LEFT JOIN Comments c ON tfp.PostId = c.PostId
LEFT JOIN PostLinks pl ON tfp.PostId = pl.PostId
WHERE
    tfp.OwnerUserId IS NOT NULL
    AND u.Reputation >= 10000
    AND tfp.PostScore >= 75
    AND COALESCE(aph.DistinctEditCount, 0) >= 2
    AND tfp.LastActivityDate > (tfp.PostCreationDate + INTERVAL '3 months')
    AND (
        (tfp.FavoriteCount > 15 AND tfp.AnswerCount > 3 AND tfp.ViewCount > 5000)
        OR (
            COALESCE(aph.WasClosedAsDuplicateOrOffTopic, FALSE)
            AND COALESCE(aph.WasReopened, FALSE)
            AND aph.LastReopenDate IS NOT NULL AND aph.FirstCloseDate IS NOT NULL
            AND aph.LastReopenDate > aph.FirstCloseDate
            AND tfp.PostScore >= 100
        )
    )
    AND tfp.PostId IN (
        SELECT p_id_filter.Id FROM Posts p_id_filter
        WHERE p_id_filter.PostTypeId = 1 AND p_id_filter.CreationDate >= DATE '2021-01-01'
        INTERSECT
        SELECT c_filter.PostId FROM Comments c_filter GROUP BY c_filter.PostId HAVING COUNT(c_filter.Id) > 5
    )
GROUP BY
    tfp.PostId, tfp.Title, tfp.PostScore, tfp.ViewCount, tfp.AnswerCount, tfp.CommentCount, tfp.FavoriteCount,
    tfp.PostCreationDate, tfp.LastActivityDate, u.DisplayName, u.Reputation, tfp.ClosedDate,
    aph.WasClosedAsDuplicateOrOffTopic, aph.WasReopened, aph.DistinctEditCount, aph.InitialBodyContent,
    aph.LatestEditBodyContent, tfp.CurrentRawBody, tfp.OwnerUserId, tfp.AcceptedAnswerId,
    aph.FirstCloseDate, aph.LastReopenDate, tfp.TagArrayText,
    -- columns used inside aggregates or window functions
    v.VoteTypeId, v.BountyAmount, c.Id, pl.LinkTypeId, pl.RelatedPostId,
    tfp.PostCreationDate, tfp.OwnerUserId, u.Reputation
HAVING
    COUNT(DISTINCT c.Id) > 5
    AND SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) >= 100
    AND (
      (CASE WHEN LOWER(tfp.TagArrayText) LIKE 'c#,%' OR LOWER(tfp.TagArrayText) LIKE '%,c#,%' OR LOWER(tfp.TagArrayText) LIKE '%,c#' OR LOWER(tfp.TagArrayText) = 'c#' THEN 1 ELSE 0 END)
      +
      (CASE WHEN LOWER(tfp.TagArrayText) LIKE 'java,%' OR LOWER(tfp.TagArrayText) LIKE '%,java,%' OR LOWER(tfp.TagArrayText) LIKE '%,java' OR LOWER(tfp.TagArrayText) = 'java' THEN 1 ELSE 0 END)
      +
      (CASE WHEN LOWER(tfp.TagArrayText) LIKE 'python,%' OR LOWER(tfp.TagArrayText) LIKE '%,python,%' OR LOWER(tfp.TagArrayText) LIKE '%,python' OR LOWER(tfp.TagArrayText) = 'python' THEN 1 ELSE 0 END)
    ) > 0
ORDER BY
    WeightedEngagementScore DESC, GlobalPostEngagementRank ASC, TotalBountyOffered DESC
LIMIT 250;