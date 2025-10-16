-- {"query": "1442.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1480} 

WITH RecursivePostHierarchy AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.AcceptedAnswerId,
        p.ParentId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        COALESCE(p.Tags, '') AS Tags,
        ARRAY[COALESCE(p.OwnerUserId::TEXT, 'unknown')] AS OwnerPathUserIds,
        1 AS Level
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Start from questions

    UNION ALL

    SELECT
        a.Id,
        a.PostTypeId,
        a.AcceptedAnswerId,
        a.ParentId,
        a.OwnerUserId,
        a.Score,
        a.ViewCount,
        a.CreationDate,
        a.Title,
        a.Tags,
        rh.OwnerPathUserIds || COALESCE(a.OwnerUserId::TEXT, 'unknown'),
        rh.Level + 1
    FROM Posts a
    INNER JOIN RecursivePostHierarchy rh ON a.ParentId = rh.Id AND a.PostTypeId = 2
),
BadgeCounts AS (
    SELECT
        UserId,
        COUNT(*) FILTER (WHERE Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE Class = 3) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges
    GROUP BY UserId
),
UserReputationQuartiles AS (
    SELECT
        Id AS UserId,
        Reputation,
        NTILE(4) OVER (ORDER BY Reputation DESC) AS ReputationQuartile
    FROM Users
),
PostVotes AS (
    SELECT
        PostId,
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(*) AS TotalVotes
    FROM Votes
    GROUP BY PostId
),
TopRepeatedTags AS (
    SELECT
        unnest(string_to_array(substring(Tags FROM '\w+'), '><') ) AS Tag,
        COUNT(*) AS Occurrences
    FROM Posts
    WHERE PostTypeId = 1 AND Tags IS NOT NULL
    GROUP BY Tag
    ORDER BY Occurrences DESC
    LIMIT 10
),
FilteredPostHistory AS (
    SELECT ph.*
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13)
),
CloseReasonSummary AS (
    SELECT 
        crt.Id,
        crt.Name,
        COUNT(fph.Id) AS ClosureCount
    FROM CloseReasonTypes crt
    LEFT JOIN FilteredPostHistory fph ON CAST(fph.Comment AS INT) = crt.Id AND fph.PostHistoryTypeId = 10
    GROUP BY crt.Id, crt.Name
)
SELECT
    rh.Level,
    rh.Id AS PostId,
    rh.PostTypeId,
    rh.AcceptedAnswerId,
    rh.ParentId,
    rh.OwnerUserId,
    CONCAT_WS(' | ', rh.Title,
        COALESCE(STRING_AGG(DISTINCT t.TagName, ', '), 'No Tags')
    ) AS QuestionTitleWithTopTags,
    rh.Score,
    rh.ViewCount,
    rh.CreationDate,
    badge_counts.TotalBadges,
    badge_counts.GoldBadges,
    badge_counts.SilverBadges,
    badge_counts.BronzeBadges,
    urq.ReputationQuartile,
    ARRAY_TO_STRING(rh.OwnerPathUserIds, '->') AS OwnerFlow,
    objUpVotes.UpVotes,
    objUpVotes.DownVotes,
    CASE
        WHEN rh.Score = 0 THEN NULL
        ELSE CAST(rh.ViewCount AS FLOAT)/NULLIF(rh.Score, 0)
    END AS ViewsPerScoreRatio,
    CONCAT(
        LOWER(u.DisplayName), ' @ ', 
        COALESCE(NULLIF(TRIM(u.Location), ''), 'Unknown Location'), ' | ",
        SUBSTRING(u.AboutMe FROM 1 FOR 40),
        CASE WHEN u.AboutMe IS NOT NULL AND OCTET_LENGTH(u.AboutMe) > 40 THEN '...' ELSE '' END
    ) AS UserShortNote,
    ph_js.CloseReasonName,
    ph_js.CloseCounts,
    SUM(MemberPosts.AnswerCountByUser) OVER (PARTITION BY rh.OwnerUserId ORDER BY rh.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeAnswersByUser,
    AVG(RAND()*100 + rh.Score) OVER (PARTITION BY rh.OwnerUserId) AS RandomAdjustedScoreAverage
FROM RecursivePostHierarchy rh
LEFT JOIN Posts q ON rh.Id = q.Id AND rh.PostTypeId=1
LEFT JOIN Tags t ON t.TagName IN (SELECT unnest(string_to_array(substring(rh.Tags, 2, LENGTH(rh.Tags)-2), '><')))
LEFT JOIN BadgeCounts badge_counts ON badge_counts.UserId = rh.OwnerUserId
LEFT JOIN Users u ON u.Id = rh.OwnerUserId
LEFT JOIN UserReputationQuartiles urq ON urq.UserId = rh.OwnerUserId
LEFT JOIN PostVotes objUpVotes ON objUpVotes.PostId = rh.Id
LEFT JOIN (
    SELECT
        ph.PostId,
        crt.Name AS CloseReasonName,
        COUNT(*) OVER (PARTITION BY crID) AS CloseCounts
    FROM 
        FilteredPostHistory ph
    INNER JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS INT)
    WHERE ph.PostHistoryTypeId = 10
) ph_js ON ph_js.PostId = rh.Id
LEFT JOIN (
    SELECT
        OwnerUserId,
        COUNT(*) AS AnswerCountByUser
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY OwnerUserId
) MemberPosts ON MemberPosts.OwnerUserId = rh.OwnerUserId
WHERE rh.Level <= 5
  AND (rh.Score > 0 OR rh.ViewCount > 500)
ORDER BY rh.CreationDate DESC
LIMIT 50

UNION

SELECT
    NULL AS Level,
    NULL AS PostId,
    NULL AS PostTypeId,
    NULL AS AcceptedAnswerId,
    NULL AS ParentId,
    NULL AS OwnerUserId,
    'CLOSURE REASON SUMMARY' AS QuestionTitleWithTopTags,
    NULL AS Score,
    NULL AS ViewCount,
    NULL AS CreationDate,
    NULL AS TotalBadges,
    NULL AS GoldBadges,
    NULL AS SilverBadges,
    NULL AS BronzeBadges,
    NULL AS ReputationQuartile,
    NULL AS OwnerFlow,
    NULL AS UpVotes,
    NULL AS DownVotes,
    NULL AS ViewsPerScoreRatio,
    NULL AS UserShortNote,
    crt.Name AS CloseReasonName,
    CloseCounts,
    NULL AS CumulativeAnswersByUser,
    NULL AS RandomAdjustedScoreAverage
FROM CloseReasonSummary crt
ORDER BY CloseCounts DESC, crt.Name
LIMIT 10;
