WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        pht.Name AS HistoryTypeName,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
UserContributionSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN COALESCE(p.Score,0) ELSE 0 END) AS TotalAnswerScore,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount END) AS AvgAnswersPerQuestion,
        MAX(u.CreationDate) AS LastUserActivityDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
HighReputationContributors AS (
    SELECT
        ucs.UserId,
        ucs.DisplayName,
        ucs.Reputation,
        ucs.QuestionCount,
        ucs.AnswerCount,
        ucs.TotalAnswerScore,
        ucs.AvgAnswersPerQuestion,
        ucs.LastUserActivityDate
    FROM UserContributionSummary ucs
    WHERE ucs.Reputation > 10000
),
PostDuplicateMap AS (
    SELECT pl.PostId, MIN(pl.RelatedPostId) AS RelatedPostId
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3
    GROUP BY pl.PostId
),
PostOwnerMap AS (
    SELECT p.Id AS PostId, p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1
)
SELECT
    pq.Id AS QuestionId,
    pq.Title AS QuestionTitle,
    h.CreationDate AS LastEditDate,
    h.HistoryTypeName AS LastEditType,
    u.DisplayName AS LastEditorDisplayName,
    COALESCE(p_dup.Title, 'No Duplicate') AS DuplicateOfTitle,
    u_contrib.DisplayName AS TopContributorDisplayName,
    u_contrib.Reputation AS TopContributorReputation,
    pq.AnswerCount,
    pq.CommentCount,
    pq.FavoriteCount,
    (pq.ViewCount * COALESCE(pq.FavoriteCount, 0) + pq.AnswerCount) AS EngagementScore,
    CASE
        WHEN pq.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN pq.CommunityOwnedDate IS NOT NULL THEN 'Community Wiki'
        ELSE 'Active'
    END AS PostStatus,
    LENGTH(pq.Body) AS BodyLength,
    SUBSTRING(pq.Tags FROM 2 FOR (CHAR_LENGTH(pq.Tags) - 2)) AS CleanedTags,
    COUNT(DISTINCT h.UserId) AS NumDistinctEditors,
    SUM(COALESCE(pq.Score,0)) AS SumScore
FROM Posts pq
JOIN RankedPostEdits h ON pq.Id = h.PostId AND h.rn = 1
LEFT JOIN PostDuplicateMap pdm ON pdm.PostId = pq.Id
LEFT JOIN Posts p_dup ON p_dup.Id = pdm.RelatedPostId
LEFT JOIN Users u ON h.UserId = u.Id
LEFT JOIN PostOwnerMap pom ON pom.PostId = pq.Id
LEFT JOIN HighReputationContributors u_contrib ON u_contrib.UserId = pom.OwnerUserId
WHERE pq.PostTypeId = 1
  AND pq.CreationDate >= DATE '2023-01-01'
  AND COALESCE(pq.Score,0) > 10
  AND u_contrib.UserId IS NOT NULL
GROUP BY
    pq.Id,
    pq.Title,
    h.CreationDate,
    h.HistoryTypeName,
    u.DisplayName,
    p_dup.Title,
    u_contrib.DisplayName,
    u_contrib.Reputation,
    pq.AnswerCount,
    pq.CommentCount,
    pq.FavoriteCount,
    pq.ViewCount,
    pq.ClosedDate,
    pq.CommunityOwnedDate,
    pq.Body,
    pq.Tags
HAVING COUNT(DISTINCT h.UserId) > 1 OR SUM(COALESCE(pq.Score,0)) > 50;