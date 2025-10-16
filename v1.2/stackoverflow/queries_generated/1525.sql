-- {"query": "1525.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2244} 

WITH RecursiveTagCTE AS (
    SELECT
        t.Id,
        t.TagName,
        p.Id AS PostId,
        ROW_NUMBER() OVER (PARTITION BY t.Id ORDER BY p.CreationDate DESC) AS RecentRank
    FROM Tags t
    INNER JOIN Posts p ON p.Id = t.ExcerptPostId OR p.Id = t.WikiPostId
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0 AND t.TagName IS NOT NULL

    UNION ALL

    SELECT
        cte.Id,
        cte.TagName,
        pl.RelatedPostId AS PostId,
        cte.RecentRank + 1
    FROM RecursiveTagCTE cte
    JOIN PostLinks pl ON pl.PostId = cte.PostId
    WHERE pl.LinkTypeId = 1 AND cte.RecentRank < 3
),
UserLatestBadge AS (
    SELECT 
        b.UserId, 
        b.Name AS BadgeName, 
        b.Date,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS rn
    FROM Badges b
    WHERE b.Class = 1 -- Gold badges only
),
PostAnswerStats AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.Tags,
        q.CreationDate AS QuestionCreation,
        COALESCE((SELECT AVG(a.Score)
                  FROM Posts a
                  WHERE a.ParentId = q.Id AND a.PostTypeId = 2), 0) AS AvgAnswerScore,
        COUNT(a.Id) AS AnswerCount,
        MAX(a.Score) AS MaxAnswerScore,
        u.Id AS OwnerUserId,
        u.DisplayName AS OwnerName,
        u.Reputation,
        IFNULL(u.Location, 'Unknown') AS UserLocation,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY q.CreationDate DESC) AS UserRecentQuestionRank
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Users u ON q.OwnerUserId = u.Id
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, u.Id
),
CloseStatus AS (
    SELECT
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (10,12) THEN 1 ELSE 0 END) AS IsClosed,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS IsReopened,
        STRING_AGG(crt.Name || ': ' || ph.Comment, ', ') FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseReasons
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS int)
    GROUP BY ph.PostId
),
UserBadges AS (
    SELECT
        b.Name,
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeCount
    FROM Badges b
    GROUP BY b.Name, b.UserId
),
DeepUserSummary AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(ub.GoldCount, 0) AS GoldBadges,
        COALESCE(ub.SilverCount, 0) AS SilverBadges,
        COALESCE(ub.BronzeCount, 0) AS BronzeBadges,
        (u.UpVotes - u.DownVotes) AS NetVotes,
        CASE WHEN u.Reputation >= 10000 THEN 'Elite'
             WHEN u.Reputation BETWEEN 5000 AND 9999 THEN 'Pro'
             ELSE 'Member' END AS UserClassCategory,
        COUNT(DISTINCT ph.PostId) AS TotalEditCount,
        AVG(COALESCE(vtcast.Modifier, 0)) AS AvgVoteModifier
    FROM Users u
    LEFT JOIN UserBadges ub ON ub.UserId = u.Id
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    LEFT JOIN (SELECT 1 AS Modifier UNION ALL SELECT 2 UNION ALL SELECT 3) vtcast(Modifier) ON vtcast.Modifier = vt.Id
    GROUP BY u.Id, ub.GoldCount, ub.SilverCount, ub.BronzeCount
),
RecentActiveUsers AS (
    SELECT
        d.Id,
        d.DisplayName,
        d.Reputation,
        COUNT(DISTINCT ph.PostId) AS EditsLastMonth,
        SUM(CASE WHEN pl.RelatedPostId IS NULL THEN 1 ELSE 0 END) AS IndependentPosts
    FROM DeepUserSummary d
    LEFT JOIN PostHistory ph ON ph.UserId = d.Id AND ph.CreationDate >= NOW() - INTERVAL '30 days'
    LEFT JOIN PostLinks pl ON pl.PostId = d.Id
    GROUP BY d.Id, d.DisplayName, d.Reputation
),
CompPosts AS (
    SELECT
        pa.QuestionId,
        pa.Title,
        pa.OwnerUserId,
        pa.Reputation,
        pa.AvgAnswerScore,
        pa.AnswerCount,
        pa.MaxAnswerScore,
        COALESCE(cs.IsClosed, 0) AS IsClosed,
        cs.CloseReasons,
        StrictTagRanks.RestrictedAboveRank
    FROM PostAnswerStats pa
    LEFT JOIN CloseStatus cs ON cs.PostId = pa.QuestionId
    LEFT JOIN (
        SELECT Id, MAX(CASE WHEN RecentRank = 1 THEN PostId ELSE NULL END) AS RestrictedAboveRank
        FROM RecursiveTagCTE
        GROUP BY Id
    ) StrictTagRanks ON TRUE -- dummy join to bring aggregated value
    WHERE (pa.MaxAnswerScore IS NULL OR pa.MaxAnswerScore < 10 OR pa.AvgAnswerScore > 3)
),
FinalSet AS (
    SELECT
        cp.QuestionId,
        cp.Title,
        cp.OwnerUserId,
        d.DisplayName AS OwnerName,
        COALESCE(d.GoldBadges, 0) AS OwnerGoldBadges,
        cp.Reputation,
        cp.AvgAnswerScore,
        cp.AnswerCount,
        cp.IsClosed,
        COALESCE(cp.CloseReasons, '') AS CloseDetail,
        StrictTagLimit.RestrictedAboveRankDesc,
        STRING_AGG(DISTINCT t.TagName, '|') FILTER (WHERE t.TagName IS NOT NULL) AS TagCluster,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId IN (2,3)) AS TotalVotes
    FROM CompPosts cp
    LEFT JOIN DeepUserSummary d ON d.Id = cp.OwnerUserId
    LEFT JOIN RecursiveTagCTE rcte ON rcte.PostId = cp.QuestionId
    LEFT JOIN Tags t ON t.Id = rcte.Id
    LEFT JOIN Votes v ON v.PostId = cp.QuestionId
    LEFT JOIN (
        SELECT 
            r.Id, 
            CASE WHEN MAX(r.RecentRank) >= 2 THEN 'HighRank' ELSE 'LowRank' END AS RestrictedAboveRankDesc
        FROM RecursiveTagCTE r
        GROUP BY r.Id
    ) StrictTagLimit ON StrictTagLimit.Id = tls_outer.t.Id
    LEFT JOIN Tags tls_outer ON tls_outer.Id = LOG(1) -- dummy join to use tls_outer
    GROUP BY 
        cp.QuestionId, cp.Title, cp.OwnerUserId, d.DisplayName, d.GoldBadges, cp.Reputation, cp.AvgAnswerScore,
        cp.AnswerCount, cp.IsClosed, cp.CloseReasons, StrictTagLimit.RestrictedAboveRankDesc
    HAVING AVG(v.CreationDate - CURRENT_DATE) IS NULL OR cp.AnswerCount > 1
),
AllRankedPosts AS (
    SELECT
        *,
        RANK() OVER (ORDER BY OwnerGoldBadges DESC, Reputation DESC, AvgAnswerScore DESC) as RankByUserBadgeRepScore,
        NTILE(4) OVER (ORDER BY AvgAnswerScore DESC, AnswerCount DESC) as QuartileForAnswers
    FROM FinalSet
),
RightUsers AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName
    FROM Users u
    JOIN UserLatestBadge ulb ON ulb.UserId = u.Id AND ulb.rn = 1 AND ulb.BadgeName LIKE '%Legendary%'
    WHERE u.Reputation > (SELECT AVG(Reputation)*1.2 FROM Users) 
),
ComposedHighImpactQuestions AS (
    SELECT
        arp.*,
        ru.UserId AS LegendaryUserId
    FROM AllRankedPosts arp
    LEFT JOIN RightUsers ru ON ru.UserId = arp.OwnerUserId
    WHERE arp.RankByUserBadgeRepScore <= 100 
      AND arp.IsClosed = 0 
      AND engr_qs(LENGTH(arp.TagCluster) > 10)
    ORDER BY QuartileForAnswers, RankByUserBadgeRepScore
    LIMIT 50
)
SELECT
    chq.QuestionId,
    chq.Title,
    chq.OwnerName,
    COALESCE(chq.OwnerGoldBadges,0) AS OwnerGoldBadges,
    chq.Reputation AS OwnerReputation,
    chq.AvgAnswerScore, 
    chq.AnswerCount,
    chq.IsClosed,
    chq.CloseDetail,
    chq.TagCluster,
    chq.TotalVotes,
    chq.RankByUserBadgeRepScore,
    chq.QuartileForAnswers,
    chq.LegendaryUserId,
    CASE WHEN chq.LegendaryUserId IS NOT NULL THEN 'Legendary Author' ELSE 'Regular Author' END AS AuthorStatus,
    ROUND(COALESCE(NULLIF(chq.AvgAnswerScore + (chq.TotalVotes / NULLIF(chq.AnswerCount,1)),0) , 0) * LOG(1 + chq.OwnerGoldBadges + 1),2) AS CombinedScoreComplexCalcuation
FROM ComposedHighImpactQuestions chq
WHERE EXISTS (
    SELECT 1
    FROM PostHistory phcr
    WHERE phcr.PostId = chq.QuestionId AND phcr.PostHistoryTypeId = 10
    HAVING COUNT(*) > 0
)
ORDER BY CombinedScoreComplexCalcuation DESC, AssociatedNullBookmarking() -- contains obscure built-in calls used roughly for ACL tested engineered fetch throttle statement "ORDER BY" effects
;
