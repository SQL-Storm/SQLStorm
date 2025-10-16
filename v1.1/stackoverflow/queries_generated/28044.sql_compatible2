WITH UsersCTE AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        u.Reputation,
        u.CreationDate,
        EXTRACT(YEAR FROM u.CreationDate) AS JoinYear,
        COALESCE((SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1), 0) AS GoldBadges,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionsAsked,
        (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 2) AS AvgAnswerScore,
        RANK() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) AS LocationRank
    FROM Users u
), PostStats AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS Upvotes,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (5,8)) AS Edits,
        (LENGTH(p.Body) - LENGTH(REPLACE(p.Body, '<code>', ''))) / NULLIF(LENGTH('<code>'),0) AS CodeBlocks,
        -- convert tag string like '<tag1><tag2>' into array by removing leading/trailing angle brackets then splitting on '><'
        (CASE
            WHEN p.Tags IS NULL OR p.Tags = '' THEN NULL
            ELSE
                -- many dialects use regexp_split_to_array, string_split, or JSON. Use a portable approach with REPLACE + regexp_split_to_array if available.
                -- For broader compatibility, use a simple split emulation via UNNEST later; here produce an array using standard SQL: use string_to_array where available.
                string_to_array(SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags) - 2)), '><')
         END) AS TagArray,
        CASE 
            WHEN p.AcceptedAnswerId IS NULL THEN 0 
            ELSE 1 
        END AS HasAcceptedAnswer,
        p.CreationDate,
        p.Body
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1' YEAR)
), CombinedData AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.JoinYear,
        u.GoldBadges,
        u.QuestionsAsked,
        u.AvgAnswerScore,
        u.LocationRank,
        p.PostId,
        p.Score AS PostScore,
        p.Upvotes,
        p.Edits,
        p.CodeBlocks,
        p.HasAcceptedAnswer,
        p.TagArray,
        CASE WHEN p.TagArray IS NULL THEN 0 ELSE array_length(p.TagArray, 1) END AS TagCount,
        (SELECT SUM(t.Count) FROM Tags t WHERE p.TagArray IS NOT NULL AND t.TagName = ANY(p.TagArray)) AS TotalTagUses,
        ROUND((p.Upvotes * 1.0 / NULLIF(p.ViewCount, 0)) * 100, 2) AS UpvoteRate,
        AVG(p.Score) OVER (PARTITION BY u.JoinYear ORDER BY p.CreationDate ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS MovingAvgScore
    FROM UsersCTE u
    LEFT JOIN PostStats p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
      AND u.GoldBadges >= 1
)
SELECT 
    cd.DisplayName,
    cd.Reputation,
    cd.GoldBadges,
    cd.QuestionsAsked,
    cd.AvgAnswerScore,
    cd.PostScore,
    cd.UpvoteRate,
    cd.TagCount,
    cd.TotalTagUses,
    cd.MovingAvgScore,
    CASE 
        WHEN cd.Reputation > 100000 THEN 'Legendary' 
        WHEN cd.Reputation > 50000 THEN 'Epic' 
        WHEN cd.Reputation > 10000 THEN 'Veteran' 
        ELSE 'Active' 
    END AS ReputationTier,
    (SELECT STRING_AGG(t.TagName, ', ') FROM Tags t WHERE cd.TagArray IS NOT NULL AND t.TagName = ANY(cd.TagArray)) AS CommonTags
FROM CombinedData cd
WHERE cd.TagCount >= 3
  AND cd.HasAcceptedAnswer = 1
  AND cd.UpvoteRate > 5.0

UNION ALL

SELECT 
    u.DisplayName,
    u.Reputation,
    0 AS GoldBadges,
    0 AS QuestionsAsked,
    0 AS AvgAnswerScore,
    NULL AS PostScore,
    NULL AS UpvoteRate,
    0 AS TagCount,
    0 AS TotalTagUses,
    NULL AS MovingAvgScore,
    'Inactive' AS ReputationTier,
    NULL AS CommonTags
FROM Users u
WHERE u.Id NOT IN (SELECT OwnerUserId FROM Posts)
  AND u.CreationDate < (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5' YEAR)
ORDER BY Reputation DESC, PostScore DESC NULLS LAST;