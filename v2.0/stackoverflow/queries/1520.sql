-- {"query": "1520.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3567}
WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.Views AS UserViews,
        COUNT(DISTINCT b_gold.Id) AS GoldBadgeCount,
        COUNT(DISTINCT b_silver.Id) AS SilverBadgeCount,
        COUNT(DISTINCT b_bronze.Id) AS BronzeBadgeCount,
        (u.UpVotes * 0.5 + u.DownVotes * -0.2 + u.Views * 0.01 + COUNT(DISTINCT b_gold.Id) * 10 + COUNT(DISTINCT b_silver.Id) * 5) AS WeightedEngagementScore,
        CASE
            WHEN u.Location LIKE '%United States%' THEN 'US'
            WHEN u.Location LIKE '%Canada%' THEN 'CA'
            WHEN u.Location IS NULL THEN 'Unknown'
            ELSE 'Other'
        END AS UserRegion
    FROM Users AS u
    LEFT JOIN Badges AS b_gold ON u.Id = b_gold.UserId AND b_gold.Class = 1
    LEFT JOIN Badges AS b_silver ON u.Id = b_silver.UserId AND b_silver.Class = 2
    LEFT JOIN Badges AS b_bronze ON u.Id = b_bronze.UserId AND b_bronze.Class = 3
    WHERE u.Reputation >= 5000
      AND u.LastAccessDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes, u.Views, u.Location
),
PostCommentSummary AS (
    SELECT
        p.Id AS PostId,
        COUNT(c.Id) AS TotalComments,
        SUM(COALESCE(c.Score, 0)) AS TotalCommentScore,
        AVG(c.Score) FILTER (WHERE c.Score IS NOT NULL) AS AvgCommentScore,
        MAX(c.CreationDate) AS LatestCommentDate,
        (SELECT MAX(c2.Score) FROM Comments AS c2 WHERE c2.PostId = p.Id AND c2.UserId IS NOT NULL) AS MaxUserCommentScore
    FROM Posts AS p
    LEFT JOIN Comments AS c ON p.Id = c.PostId
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.Id
),
PostEditHistoryDetails AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate AS EditDate,
        ph.UserId AS EditorUserId,
        LAG(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousEditDate,
        EXTRACT(EPOCH FROM (ph.CreationDate - LAG(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate))) AS TimeSinceLastEditSeconds,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn_latest_edit,
        FIRST_VALUE(ph.UserId) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate ASC) AS OriginalCreatorId
    FROM PostHistory AS ph
    WHERE ph.PostHistoryTypeId IN (2, 5, 8)
),
AggregatedPostHistory AS (
    SELECT
        peh.PostId,
        COUNT(peh.EditDate) AS TotalBodyEdits,
        AVG(peh.TimeSinceLastEditSeconds) FILTER (WHERE peh.TimeSinceLastEditSeconds > 0) AS AvgEditIntervalSeconds,
        MAX(peh.EditDate) AS LastBodyEditDate,
        MIN(peh.EditDate) AS FirstBodyEditDate,
        SUM(CASE WHEN peh.PostHistoryTypeId = 8 THEN 1 ELSE 0 END) AS RollbackCount,
        MAX(peh.OriginalCreatorId) AS OriginalOwnerUserId
    FROM PostEditHistoryDetails AS peh
    GROUP BY peh.PostId
),
BasePostData AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.CreationDate,
        p.LastActivityDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
        p.OwnerUserId,
        p.Body,
        p.Title,
        p.Tags,
        p.CommunityOwnedDate,
        p.AcceptedAnswerId,
        p.ParentId,
        EXISTS (
            SELECT 1
            FROM PostHistory AS ph_close
            WHERE ph_close.PostId = p.Id
              AND ph_close.PostHistoryTypeId = 10
              AND ph_close.CreationDate > p.CreationDate
        ) AS WasClosedEver,
        (
            SELECT COUNT(v.Id)
            FROM Votes AS v
            WHERE v.PostId = p.Id
              AND v.VoteTypeId = 2
              AND v.CreationDate BETWEEN p.CreationDate AND p.LastActivityDate
        ) AS UpVoteCountDuringActivePeriod,
        CASE
            WHEN p.Body LIKE '%<pre><code>%' OR p.Body LIKE '%<code>%' THEN 'CodeSnippetPresent'
            WHEN LENGTH(p.Body) > 5000 THEN 'VeryLongBody'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'CommunityOwned'
            ELSE 'Standard'
        END AS PostComplexityCategory
    FROM Posts AS p
    INNER JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    WHERE p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5 years')
      AND p.ViewCount > 50
      AND (p.OwnerUserId IS NOT NULL OR p.LastEditorUserId IS NOT NULL)
      AND NOT EXISTS (
          SELECT 1 FROM PostHistory AS ph_del WHERE ph_del.PostId = p.Id AND ph_del.PostHistoryTypeId = 12
      )
)
SELECT
    bpd.PostId,
    bpd.Title,
    bpd.PostTypeName,
    bpd.CreationDate AS PostCreationDate,
    bpd.LastActivityDate,
    bpd.PostScore,
    bpd.ViewCount,
    bpd.AnswerCount,
    bpd.FavoriteCount,
    ue.DisplayName AS PostOwnerDisplayName,
    ue.Reputation AS PostOwnerReputation,
    ue.WeightedEngagementScore,
    pcs.TotalComments,
    pcs.TotalCommentScore,
    pcs.AvgCommentScore,
    aph.TotalBodyEdits,
    aph.AvgEditIntervalSeconds,
    aph.RollbackCount,
    ql.LinkCount AS RelatedQuestionLinks,
    COALESCE(t.TagName, 'No Tag') AS PrimaryTagName,
    STRING_AGG(CASE WHEN b.Class = 1 THEN b.Name ELSE NULL END, '; ' ORDER BY b.Name) AS GoldBadgesOnPost,
    bpd.WasClosedEver,
    bpd.UpVoteCountDuringActivePeriod,
    bpd.PostComplexityCategory,
    DENSE_RANK() OVER (ORDER BY bpd.PostScore DESC, bpd.ViewCount DESC) AS GlobalPostRankByPopularity,
    NTILE(5) OVER (PARTITION BY bpd.PostTypeName ORDER BY bpd.CreationDate) AS CreationDateQuintileByPostType
FROM BasePostData AS bpd
LEFT JOIN UserEngagement AS ue ON bpd.OwnerUserId = ue.UserId
LEFT JOIN PostCommentSummary AS pcs ON bpd.PostId = pcs.PostId
LEFT JOIN AggregatedPostHistory AS aph ON bpd.PostId = aph.PostId
LEFT JOIN (
    SELECT PostId, COUNT(Id) AS LinkCount
    FROM PostLinks
    WHERE LinkTypeId = 1
    GROUP BY PostId
) AS ql ON bpd.PostId = ql.PostId
LEFT JOIN Tags AS t ON (
    SELECT SPLIT_PART(SUBSTRING(bpd.Tags FROM 2 FOR LENGTH(bpd.Tags) - 2), '><', 1)
    WHERE bpd.Tags IS NOT NULL AND LENGTH(bpd.Tags) > 2
) = t.TagName
LEFT JOIN Badges AS b ON bpd.OwnerUserId = b.UserId AND b.Class = 1
WHERE bpd.PostTypeId = 1
  AND (bpd.AcceptedAnswerId IS NOT NULL OR bpd.AnswerCount > 2)
  AND (bpd.Tags IS NOT NULL AND (bpd.Tags LIKE '%<sql>%' OR bpd.Tags LIKE '%<database>%'))
GROUP BY
    bpd.PostId, bpd.Title, bpd.PostTypeName, bpd.CreationDate, bpd.LastActivityDate, bpd.PostScore, bpd.ViewCount, bpd.AnswerCount,
    bpd.FavoriteCount, ue.DisplayName, ue.Reputation, ue.WeightedEngagementScore,
    pcs.TotalComments, pcs.TotalCommentScore, pcs.AvgCommentScore,
    aph.TotalBodyEdits, aph.AvgEditIntervalSeconds, aph.RollbackCount, ql.LinkCount,
    t.TagName, bpd.WasClosedEver, bpd.UpVoteCountDuringActivePeriod, bpd.PostComplexityCategory, bpd.PostId, bpd.CreationDate, bpd.PostScore
HAVING
    COUNT(CASE WHEN b.Class = 1 THEN b.Id END) >= 1 OR ue.Reputation > 20000

UNION ALL

SELECT
    bpd.PostId,
    parent_q.Title AS Title,
    bpd.PostTypeName,
    bpd.CreationDate AS PostCreationDate,
    bpd.LastActivityDate,
    bpd.PostScore,
    NULL AS ViewCount,
    NULL AS AnswerCount,
    bpd.FavoriteCount,
    ue.DisplayName AS PostOwnerDisplayName,
    ue.Reputation AS PostOwnerReputation,
    ue.WeightedEngagementScore,
    pcs.TotalComments,
    pcs.TotalCommentScore,
    pcs.AvgCommentScore,
    aph.TotalBodyEdits,
    aph.AvgEditIntervalSeconds,
    aph.RollbackCount,
    ql.LinkCount AS RelatedQuestionLinks,
    COALESCE(t.TagName, 'No Tag') AS PrimaryTagName,
    STRING_AGG(CASE WHEN b.Class = 1 THEN b.Name ELSE NULL END, '; ' ORDER BY b.Name) AS GoldBadgesOnPost,
    bpd.WasClosedEver,
    bpd.UpVoteCountDuringActivePeriod,
    bpd.PostComplexityCategory,
    DENSE_RANK() OVER (ORDER BY bpd.PostScore DESC) AS GlobalPostRankByPopularity,
    NTILE(5) OVER (PARTITION BY bpd.PostTypeName ORDER BY bpd.CreationDate) AS CreationDateQuintileByPostType
FROM BasePostData AS bpd
LEFT JOIN UserEngagement AS ue ON bpd.OwnerUserId = ue.UserId
LEFT JOIN PostCommentSummary AS pcs ON bpd.PostId = pcs.PostId
LEFT JOIN AggregatedPostHistory AS aph ON bpd.PostId = aph.PostId
LEFT JOIN (
    SELECT PostId, COUNT(Id) AS LinkCount
    FROM PostLinks
    WHERE LinkTypeId = 1
    GROUP BY PostId
) AS ql ON bpd.PostId = ql.PostId
INNER JOIN Posts AS parent_q ON bpd.ParentId = parent_q.Id
LEFT JOIN Tags AS t ON (
    SELECT SPLIT_PART(SUBSTRING(parent_q.Tags FROM 2 FOR LENGTH(parent_q.Tags) - 2), '><', 1)
    WHERE parent_q.Tags IS NOT NULL AND LENGTH(parent_q.Tags) > 2
) = t.TagName
LEFT JOIN Badges AS b ON bpd.OwnerUserId = b.UserId AND b.Class = 1
WHERE bpd.PostTypeId = 2
  AND bpd.PostScore >= 5
  AND EXISTS (
      SELECT 1 FROM Posts AS p_q WHERE p_q.Id = bpd.ParentId AND (p_q.Tags LIKE '%<sql>%' OR p_q.Tags LIKE '%<database>%')
  )
GROUP BY
    bpd.PostId, parent_q.Title, bpd.PostTypeName, bpd.CreationDate, bpd.LastActivityDate, bpd.PostScore,
    bpd.FavoriteCount, ue.DisplayName, ue.Reputation, ue.WeightedEngagementScore,
    pcs.TotalComments, pcs.TotalCommentScore, pcs.AvgCommentScore,
    aph.TotalBodyEdits, aph.AvgEditIntervalSeconds, aph.RollbackCount, ql.LinkCount,
    t.TagName, bpd.WasClosedEver, bpd.UpVoteCountDuringActivePeriod, bpd.PostComplexityCategory, bpd.PostId, bpd.CreationDate, bpd.PostScore
HAVING
    COUNT(CASE WHEN b.Class = 1 THEN b.Id END) >= 1 OR ue.Reputation > 15000

ORDER BY
    WeightedEngagementScore DESC, PostScore DESC, PostCreationDate DESC
LIMIT 2000;