-- {"query": "21022.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2168, "output_tokens": 1034} 

WITH ActiveUsers AS (
    SELECT u.Id, u.Reputation, u.CreationDate,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as RepRank,
           LAG(u.Reputation) OVER (ORDER BY u.CreationDate) as PrevRep
    FROM Users u
    WHERE u.Reputation > 100
      AND u.LastAccessDate > CURRENT_DATE - INTERVAL '1 year'
),
QuestionMetrics AS (
    SELECT p.Id as QuestionId, p.OwnerUserId,
           COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) as UpVotes,
           COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) as DownVotes,
           AVG(v.BountyAmount) FILTER (WHERE v.VoteTypeId = 8) as AvgBounty,
           STRING_AGG(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN COALESCE(ph.Comment, 'Unknown') ELSE NULL END, '; ') as CloseReasons
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
    WHERE p.PostTypeId = 1
      AND p.CreationDate > CURRENT_DATE - INTERVAL '2 years'
    GROUP BY p.Id, p.OwnerUserId
),
HighImpactQuestions AS (
    SELECT qm.QuestionId, qm.OwnerUserId, qm.UpVotes,
           CASE 
               WHEN qm.UpVotes > qm.DownVotes * 3 THEN 'Highly Accepted'
               WHEN qm.CloseReasons IS NOT NULL THEN 'Controversial'
               ELSE 'Neutral'
           END as ImpactCategory,
           ROW_NUMBER() OVER (PARTITION BY qm.OwnerUserId ORDER BY qm.UpVotes DESC) as UserQuestionRank
    FROM QuestionMetrics qm
    WHERE qm.UpVotes > 10 OR (qm.DownVotes > 0 AND qm.CloseReasons IS NOT NULL)
),
BadgeAchievements AS (
    SELECT b.UserId,
           COUNT(CASE WHEN b.Class = 1 THEN 1 END) as GoldBadges,
           COUNT(CASE WHEN b.Class = 2 THEN 1 END) as SilverBadges,
           STRING_AGG(DISTINCT b.Name, ', ') FILTER (WHERE b.TagBased = TRUE) as TagBadges
    FROM Badges b
    WHERE b.Date > CURRENT_DATE - INTERVAL '1 year'
    GROUP BY b.UserId
),
LinkedPosts AS (
    SELECT pl.PostId,
           COUNT(DISTINCT pl.RelatedPostId) as OutboundLinks,
           COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId END) as DuplicateLinks
    FROM PostLinks pl
    WHERE pl.CreationDate > CURRENT_DATE - INTERVAL '1 year'
    GROUP BY pl.PostId
)
SELECT 
    au.Id as UserId,
    au.DisplayName,
    au.Reputation,
    au.RepRank,
    COALESCE(hiq.UpVotes, 0) as TotalQuestionUpvotes,
    COALESCE(hiq.ImpactCategory, 'No Impact') as QuestionImpact,
    ba.GoldBadges,
    ba.SilverBadges,
    COALESCE(lp.OutboundLinks, 0) + COALESCE(CASE WHEN hiq.DuplicateLinks > 0 THEN hiq.DuplicateLinks ELSE 0 END, 0) as TotalLinks,
    CASE 
        WHEN au.RepRank <= 10 AND ba.GoldBadges >= 3 THEN 'Elite'
        WHEN au.Reputation > 1000 OR hiq.UpVotes > 50 THEN 'Influencer'
        WHEN au.PrevRep IS NULL OR au.Reputation > COALESCE(au.PrevRep, 0) * 1.5 THEN 'Rising Star'
        ELSE 'Standard'
    END as UserTier,
    LENGTH(COALESCE(ba.TagBadges, '')) + LENGTH(COALESCE(hiq.CloseReasons, '')) as EngagementStringLength,
    (COALESCE(hiq.UpVotes, 0) - COALESCE(hiq.DownVotes, 0)) / NULLIF(au.RepRank, 0) as ImpactRatio
FROM ActiveUsers au
LEFT JOIN HighImpactQuestions hiq ON au.Id = hiq.OwnerUserId AND hiq.UserQuestionRank <= 5
LEFT JOIN BadgeAchievements ba ON au.Id = ba.UserId
LEFT JOIN LinkedPosts lp ON au.Id = (SELECT p.OwnerUserId FROM Posts p WHERE p.Id = lp.PostId LIMIT 1)
WHERE (au.RepRank <= 100 
       OR hiq.UpVotes > 20 
       OR ba.GoldBadges > 1)
  AND (hiq.ImpactCategory != 'Controversial' OR au.Reputation > 5000)
ORDER BY ImpactRatio DESC NULLS LAST, au.RepRank
LIMIT 50;
