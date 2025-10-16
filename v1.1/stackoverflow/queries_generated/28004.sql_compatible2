WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        ROW_NUMBER() OVER (PARTITION BY b.Class ORDER BY u.Reputation DESC) AS BadgeClassRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation, u.UpVotes, u.DownVotes, b.Class
), PostAnalysis AS (
    SELECT
        p.OwnerUserId,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseVotes,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId = 11) AS ReopenVotes,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotes
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.CreationDate BETWEEN DATE '2010-01-01' AND DATE '2023-12-31'
    GROUP BY p.OwnerUserId
)
SELECT 
    u.Id,
    u.DisplayName,
    COALESCE(us.GoldBadges, 0) + COALESCE(us.SilverBadges, 0) * 0.5 + COALESCE(us.BronzeBadges, 0) * 0.25 AS WeightedBadgeScore,
    CASE WHEN pa.AvgAnswerScore IS NULL OR pa.AvgAnswerScore = 0 THEN NULL ELSE pa.AvgQuestionScore / pa.AvgAnswerScore END AS QuestionAnswerRatio,
    (COALESCE(us.UpVotes,0) - COALESCE(us.DownVotes,0)) * CASE WHEN u.Reputation IS NULL THEN 0 ELSE LOG(u.Reputation + 1) END AS ReputationImpact,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id AND c.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id)) AS SelfCommentCount,
    COALESCE(
        NULLIF(
            -- compute number of tags by splitting the tag string like '<tag1><tag2>' into elements:
            -- remove leading and trailing angle brackets then count occurrences of '><' plus 1 when not empty
            CASE
                WHEN p.Tags IS NULL OR LENGTH(TRIM(p.Tags)) = 0 THEN 0
                ELSE (
                    CASE
                        WHEN POSITION('><' IN SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2)) = 0 THEN 1
                        ELSE LENGTH(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2)) - LENGTH(REPLACE(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><', '')) 
                             -- each '><' removal reduces length by 2, so count = occurrences + 1
                             -- occurrences = (difference in length) / 2
                        / 2 + 1
                    END
                )
            END,
            0
        ),
        0
    ) AS AvgTagsPerPost,
    CASE 
        WHEN COALESCE(pa.CloseVotes,0) > COALESCE(pa.ReopenVotes,0) THEN 'Controversial'
        WHEN COALESCE(pa.TotalUpvotes,0) > COALESCE(pa.TotalDownvotes,0) * 2 THEN 'HighQuality'
        WHEN ph.Comment LIKE '%101%' THEN 'DuplicateCloser'
        ELSE 'Neutral'
    END AS UserCategory
FROM Users u
LEFT JOIN UserStats us ON u.Id = us.UserId
LEFT JOIN PostAnalysis pa ON u.Id = pa.OwnerUserId
LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
WHERE u.Reputation > 1000
    AND (COALESCE(pa.AvgQuestionScore,0) > 5 OR COALESCE(pa.AvgAnswerScore,0) > 10)
    AND (COALESCE(us.GoldBadges,0) > 0 OR COALESCE(us.SilverBadges,0) > 5)
    AND p.ClosedDate IS NULL
GROUP BY 
    u.Id,
    u.DisplayName,
    COALESCE(us.GoldBadges, 0) + COALESCE(us.SilverBadges, 0) * 0.5 + COALESCE(us.BronzeBadges, 0) * 0.25,
    CASE WHEN pa.AvgAnswerScore IS NULL OR pa.AvgAnswerScore = 0 THEN NULL ELSE pa.AvgQuestionScore / pa.AvgAnswerScore END,
    (COALESCE(us.UpVotes,0) - COALESCE(us.DownVotes,0)) * CASE WHEN u.Reputation IS NULL THEN 0 ELSE LOG(u.Reputation + 1) END,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id AND c.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id)),
    COALESCE(
        NULLIF(
            CASE
                WHEN p.Tags IS NULL OR LENGTH(TRIM(p.Tags)) = 0 THEN 0
                ELSE (
                    CASE
                        WHEN POSITION('><' IN SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2)) = 0 THEN 1
                        ELSE LENGTH(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2)) - LENGTH(REPLACE(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><', ''))
                        / 2 + 1
                    END
                )
            END,
            0
        ),
        0
    ),
    CASE 
        WHEN COALESCE(pa.CloseVotes,0) > COALESCE(pa.ReopenVotes,0) THEN 'Controversial'
        WHEN COALESCE(pa.TotalUpvotes,0) > COALESCE(pa.TotalDownvotes,0) * 2 THEN 'HighQuality'
        WHEN ph.Comment LIKE '%101%' THEN 'DuplicateCloser'
        ELSE 'Neutral'
    END,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.UpVotes,
    us.DownVotes,
    u.Reputation,
    pa.AvgQuestionScore,
    pa.AvgAnswerScore,
    pa.CloseVotes,
    pa.ReopenVotes,
    pa.TotalUpvotes,
    pa.TotalDownvotes,
    p.Tags,
    ph.Comment
ORDER BY WeightedBadgeScore DESC, ReputationImpact DESC
LIMIT 100;