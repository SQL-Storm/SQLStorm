-- {"query": "4192.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 987} 

WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        pht.Name AS HistoryTypeName,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
UserContributionSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE NULL END) AS AvgAnswersPerQuestion,
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
    SUBSTRING(pq.Tags, 2, LENGTH(pq.Tags) - 2) AS CleanedTags
FROM Posts pq
JOIN RankedPostEdits h ON pq.Id = h.PostId AND h.rn = 1
LEFT JOIN Posts p_dup ON pq.Id = (SELECT RelatedPostId FROM PostLinks WHERE PostId = pq.Id AND LinkTypeId = 3)
LEFT JOIN Users u ON h.UserId = u.Id
LEFT JOIN HighReputationContributors u_contrib ON u_contrib.UserId = (
    SELECT UserId
    FROM UserContributionSummary
    WHERE Id = (
        SELECT OwnerUserId
        FROM Posts
        WHERE Id = pq.Id
    )
    ORDER BY Reputation DESC
    LIMIT 1
)
WHERE pq.PostTypeId = 1 -- Questions only
  AND pq.CreationDate >= '2023-01-01'
  AND pq.Score > 10
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
    pq.PostStatus,
    pq.ClosedDate,
    pq.CommunityOwnedDate,
    pq.Body,
    pq.Tags
HAVING COUNT(DISTINCT h.UserId) > 1 OR SUM(pq.Score) > 50;
