-- {"query": "1292.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3170}
WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.UpVotes,
        u.DownVotes,
        u.Views AS UserProfileViews,
        COALESCE(b.GoldBadges, 0) AS GoldBadges,
        COALESCE(b.SilverBadges, 0) AS SilverBadges,
        COALESCE(b.BronzeBadges, 0) AS BronzeBadges,
        NTILE(100) OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS ReputationPercentile,
        CASE
            WHEN (u.UpVotes + u.DownVotes) > 0 THEN CAST(u.UpVotes AS NUMERIC) / (u.UpVotes + u.DownVotes)
            ELSE 0.0
        END AS VoteRatio,
        COALESCE(u.Location, 'Earth') AS UserLocation_Coalesced,
        (SELECT COUNT(p.Id) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.CreationDate >= u.CreationDate - INTERVAL '1 year') AS RecentQuestionCount,
        (SELECT COUNT(c.Id) FROM Comments c WHERE c.UserId = u.Id AND c.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90 days') AS Last90DayCommentCount
    FROM
        Users u
    LEFT JOIN (
        SELECT
            UserId,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
            SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
        FROM Badges
        GROUP BY UserId
    ) b ON u.Id = b.UserId
    WHERE
        u.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '5 years'
        AND u.Reputation > 500
),
PostQualityMetrics AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Tags,
        p.CreationDate AS PostCreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ph_edits.LastEditCount,
        ph_edits.SelfEditCount,
        p.AcceptedAnswerId,
        (SELECT p_ans.Score FROM Posts p_ans WHERE p_ans.Id = p.AcceptedAnswerId AND p_ans.PostTypeId = 2) AS AcceptedAnswerScore,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'CommunityOwned'
            WHEN (p.LastActivityDate IS NULL OR p.LastActivityDate < p.CreationDate + INTERVAL '180 days') AND p.AnswerCount = 0 THEN 'StaleNoActivity'
            ELSE 'Active'
        END AS PostStatus,
        NULLIF(p.ViewCount, 0) AS ViewCount_NonNull,
        -- convert tags like '<tag1><tag2>' into array of tag strings
        REGEXP_SPLIT_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags)-2), '><') AS TagArray,
        (SELECT MIN(ph_hist.CreationDate) FROM PostHistory ph_hist WHERE ph_hist.PostId = p.Id AND ph_hist.PostHistoryTypeId IN (4,5,6) AND ph_hist.UserId IS NOT NULL) AS FirstEditDateByAnyUser
    FROM
        Posts p
    LEFT JOIN (
        SELECT
            ph_inner.PostId AS PostId,
            COUNT(ph_inner.Id) AS LastEditCount,
            SUM(CASE WHEN ph_inner.UserId = p_inner.OwnerUserId THEN 1 ELSE 0 END) AS SelfEditCount
        FROM
            PostHistory ph_inner
        JOIN
            Posts p_inner ON ph_inner.PostId = p_inner.Id
        WHERE
            ph_inner.PostHistoryTypeId IN (4, 5, 6)
        GROUP BY
            ph_inner.PostId, p_inner.OwnerUserId
    ) ph_edits ON p.Id = ph_edits.PostId
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '4 years'
        AND p.Score >= 5
),
RankedTagPerformance AS (
    SELECT
        pqm.PostId,
        pqm.Title,
        pqm.OwnerUserId,
        pqm.Score,
        pqm.ViewCount,
        pqm.TagArray,
        t.TagName,
        RANK() OVER (PARTITION BY t.TagName ORDER BY pqm.Score DESC, pqm.ViewCount DESC) AS RankInTag,
        AVG(pqm.Score) OVER (PARTITION BY t.TagName) AS AvgScoreForTag,
        MAX(COALESCE(pqm.LastEditCount, 0)) OVER (PARTITION BY t.TagName) AS MaxEditsInTag
    FROM
        PostQualityMetrics pqm
    JOIN Tags t ON t.TagName = ANY(pqm.TagArray)
    WHERE
        pqm.Score >= 10
        AND CARDINALITY(pqm.TagArray) IS NOT NULL AND CARDINALITY(pqm.TagArray) > 0
),
RecentAnswerPerformance AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId AS AnswerOwnerUserId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreationDate,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRankForQuestion
    FROM
        Posts a
    WHERE
        a.PostTypeId = 2
        AND a.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '2 years'
        AND a.Score > 0
),
PotentialDuplicateCandidates AS (
    SELECT
        p1.Id AS Post1Id,
        p1.Title AS Post1Title,
        p1.CreationDate AS Post1CreationDate,
        p2.Id AS Post2Id,
        p2.Title AS Post2Title,
        p2.CreationDate AS Post2CreationDate,
        p1.OwnerUserId AS Post1OwnerUserId,
        p2.OwnerUserId AS Post2OwnerUserId
    FROM
        Posts p1
    JOIN
        Posts p2 ON p1.Id < p2.Id
    WHERE
        p1.PostTypeId = 1 AND p2.PostTypeId = 1
        AND p1.Title IS NOT NULL AND p2.Title IS NOT NULL
        AND p1.CreationDate BETWEEN p2.CreationDate - INTERVAL '90 days' AND p2.CreationDate + INTERVAL '90 days'
        AND REPLACE(LOWER(SUBSTRING(p1.Title FROM 1 FOR 30)), ' ', '') LIKE '%' || REPLACE(LOWER(SUBSTRING(p2.Title FROM 1 FOR 30)), ' ', '') || '%'
    LIMIT 2000
)
SELECT
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.ReputationPercentile,
    ue.VoteRatio,
    ue.GoldBadges,
    ue.RecentQuestionCount,
    ue.Last90DayCommentCount,
    pqm.PostId,
    pqm.Title,
    pqm.PostCreationDate,
    pqm.Score AS QuestionScore,
    pqm.ViewCount AS QuestionViews,
    pqm.AnswerCount AS QuestionAnswerCount,
    pqm.PostStatus,
    COALESCE(pqm.LastEditCount, 0) AS TotalEditsOnQuestion,
    COALESCE(pqm.SelfEditCount, 0) AS SelfEditsOnQuestion,
    COALESCE(pqm.AcceptedAnswerScore, 0) AS EffectiveAcceptedAnswerScore,
    COALESCE(rp.RankInTag, 9999) AS QuestionRankInTopTag,
    rp.TagName AS TopContributingTag,
    (
        SELECT SUM(v.BountyAmount)
        FROM Votes v
        WHERE v.PostId = pqm.PostId AND v.VoteTypeId = 8
    ) AS TotalBountyAmountOffered,
    UPPER(SUBSTRING(pqm.Title FROM 1 FOR 5)) || '...' || LOWER(SUBSTRING(pqm.Title FROM GREATEST(1, CHAR_LENGTH(pqm.Title) - 4) FOR CHAR_LENGTH(pqm.Title))) AS TitleSnippet,
    (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - ue.CreationDate) AS UserAgeFromCreation,
    CASE
        WHEN ue.Reputation > 20000 AND pqm.Score > 100 THEN 'Very High Impact'
        WHEN ue.Reputation > 5000 AND pqm.Score > 30 THEN 'High Impact'
        WHEN ue.Reputation > 1000 AND pqm.Score > 10 THEN 'Moderate Impact'
        ELSE 'Regular Contributor'
    END AS ImpactCategory,
    AVG(rap.AnswerScore) OVER (PARTITION BY ue.UserId) AS AvgAnswerScoreByThisUser,
    MAX(rap.AnswerRankForQuestion) OVER (PARTITION BY ue.UserId) AS BestAnswerRankForUser,
    (SELECT COUNT(DISTINCT l.RelatedPostId) FROM PostLinks l WHERE l.PostId = pqm.PostId AND l.LinkTypeId = 3) AS NumberOfDuplicatesLinked
FROM
    UserEngagement ue
INNER JOIN
    PostQualityMetrics pqm ON ue.UserId = pqm.OwnerUserId
LEFT JOIN
    RankedTagPerformance rp ON pqm.PostId = rp.PostId AND rp.RankInTag <= 3
LEFT JOIN
    RecentAnswerPerformance rap ON ue.UserId = rap.AnswerOwnerUserId AND rap.QuestionId = pqm.PostId
WHERE
    ue.ReputationPercentile <= 15
    AND pqm.PostStatus IN ('Active', 'CommunityOwned')
    AND EXISTS (
        SELECT 1 FROM Badges b_sub WHERE b_sub.UserId = ue.UserId AND LOWER(b_sub.Name) LIKE '%gold%' AND b_sub.TagBased = FALSE
    )
    AND NOT EXISTS (
        SELECT 1 FROM PotentialDuplicateCandidates pdc WHERE pdc.Post1Id = pqm.PostId OR pdc.Post2Id = pqm.PostId
    )
    AND pqm.Title IS NOT NULL
GROUP BY
    ue.UserId, ue.DisplayName, ue.Reputation, ue.ReputationPercentile, ue.VoteRatio, ue.GoldBadges, ue.RecentQuestionCount,
    ue.Last90DayCommentCount, pqm.PostId, pqm.Title, pqm.PostCreationDate, pqm.Score, pqm.ViewCount, pqm.AnswerCount,
    pqm.PostStatus, pqm.LastEditCount, pqm.SelfEditCount, pqm.AcceptedAnswerScore, rp.RankInTag, rp.TagName, ue.CreationDate,
    pqm.Tags, ue.UpVotes, ue.DownVotes, ue.LastAccessDate, ue.UserProfileViews, ue.SilverBadges, ue.BronzeBadges,
    pqm.CommentCount, pqm.FavoriteCount, pqm.AcceptedAnswerId, pqm.ViewCount_NonNull, pqm.TagArray, pqm.FirstEditDateByAnyUser,
    rap.AnswerOwnerUserId, rap.AnswerScore, rap.AnswerRankForQuestion
HAVING
    COUNT(rap.AnswerId) > 0 OR pqm.AnswerCount > 0
ORDER BY
    ue.Reputation DESC, pqm.Score DESC, ue.UserId, pqm.PostId
LIMIT 5000;