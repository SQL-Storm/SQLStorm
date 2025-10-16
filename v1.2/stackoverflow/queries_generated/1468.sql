-- {"query": "1468.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1411} 
WITH RecursiveTagCTE AS (
    -- Recursively find tags related by duplicates of their excerpt posts to form clusters of related tags
    SELECT t.Id AS TagId, t.TagName, t.ExcerptPostId, p.Id AS PostId, 1 AS Level
    FROM Tags t
    LEFT JOIN Posts p ON p.Id = t.ExcerptPostId
    WHERE t.ExcerptPostId IS NOT NULL

    UNION ALL

    SELECT t2.Id, t2.TagName, t2.ExcerptPostId, pl.RelatedPostId, r.Level + 1
    FROM RecursiveTagCTE r
    INNER JOIN PostLinks pl ON pl.PostId = r.PostId AND pl.LinkTypeId = 3 -- duplicates
    INNER JOIN Tags t2 ON t2.ExcerptPostId = pl.RelatedPostId
    WHERE r.Level < 5
),

HighRepUsers AS (
    SELECT Id, DisplayName, Reputation,
           COALESCE(Location, 'Unknown') AS LocationNormalized,
           LEFT(AboutMe, 100) AS AboutSnippet
    FROM Users
    WHERE Reputation > 10000 
),

UserActivityWin AS (
    -- Calc user activity by total post score and vote counts combined with advanced window logic per location
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.LocationNormalized,
        PrimedBy11 = CASE WHEN u.Reputation > 100000 THEN 1 ELSE 0 END,
        TotalPostScore = COALESCE(SUM(p.Score), 0),
        TotalUpVotes = COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0),
        TotalDownVotes = COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0),
        UserRankInLoc = ROW_NUMBER() OVER (PARTITION BY u.LocationNormalized ORDER BY COALESCE(SUM(p.Score),0) + COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END),0)*2 - COALESCE(SUM(CASE WHEN v.VoteTypeId=3 THEN 1 ELSE 0 END),0)*2 DESC),
        AvgScorePerPost = AVG(COALESCE(p.Score, 0)) OVER (PARTITION BY u.Id)
    FROM HighRepUsers u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName, u.LocationNormalized, u.Reputation
),

RecentClosedQuestions AS (
    -- Find recent questions that have been closed but with a correlated select checking for reopening attempts in history
    SELECT 
        q.Id AS QuestionId, q.Title, q.OwnerUserId,
        ch.PostHistory.ClosingTypeName, ch.PostHistory.ClosedDate,
        CASE 
            WHEN EXISTS (
               SELECT 1 FROM PostHistory ph
               WHERE ph.PostId = q.Id AND ph.PostHistoryTypeId IN (11) AND ph.CreationDate > ch.PostHistory.ClosedDate
            ) THEN 1 ELSE 0 END AS IsReopenedAfterClose
    FROM Posts q
    INNER JOIN (
      SELECT PostId, pht.Name AS ClosingTypeName, MIN(ph.CreationDate) AS ClosedDate
      FROM PostHistory ph 
      INNER JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id AND ph.PostHistoryTypeId = 10
      GROUP BY ph.PostId, pht.Name
    ) ch ON q.Id = ch.PostId
    WHERE q.PostTypeId = 1 AND ch.ClosedDate > CURRENT_DATE - INTERVAL '100 days'
),

BadgeSummary AS (
    -- Aggregate user badges if they earned distinct tag-based badges and classic badges in last year with NULL fallback and string aggregation
    SELECT 
        UserId,
        COUNT(DISTINCT CASE WHEN TagBased = 1 THEN Name ELSE NULL END) AS DistinctTagBasedBadgeCount,
        COUNT(DISTINCT CASE WHEN TagBased = 0 THEN Name ELSE NULL END) AS DistinctNamedBadgeCount,
        STRING_AGG(DISTINCT COALESCE(Name, 'Unknown'), ',' ) AS AllBadgeNames,
        MAX(Date) AS LatestBadgeEarned
    FROM Badges
    WHERE Date > CURRENT_DATE - INTERVAL '1 year'
    GROUP BY UserId
),

CombinedLeadboard AS (
    SELECT
        uud.UserId,
        uud.DisplayName,
        uud.LocationNormalized,
        uud.Reputation,
        uud.TotalPostScore,
        uud.TotalUpVotes,
        uud.TotalDownVotes,
        us.DistinctTagBasedBadgeCount,
        us.DistinctNamedBadgeCount,
        us.AllBadgeNames,
        uu.MaxAcceptedAnswerScore,
        RANK() OVER (ORDER BY uud.TotalPostScore + uud.TotalUpVotes * 2 - uud.TotalDownVotes * 2 DESC) AS OverallUserRank
    FROM UserActivityWin uud
    LEFT JOIN BadgeSummary us ON us.UserId = uud.UserId
    LEFT JOIN (
       -- Correlated subquery per user for accepted answer max score dynamically recalculated using filter json ops
       SELECT OwnerUserId,
              MAX(Score) AS MaxAcceptedAnswerScore
       FROM Posts a
       WHERE a.PostTypeId = 2 AND EXISTS (
          SELECT 1 FROM Posts q WHERE q.AcceptedAnswerId = a.Id
       )
       GROUP BY OwnerUserId
    ) uu ON uu.OwnerUserId = uud.UserId
-- filter by самых крутых only or not done at SQL leveling for complexity benchmarking
)

SELECT
    ll.UserId,
    ll.DisplayName,
    ll.LocationNormalized,
    ll.Reputation,
    ll.TotalPostScore,
    ll.TotalUpVotes,
    ll.TotalDownVotes,
    ll.DistinctTagBasedBadgeCount,
    ll.DistinctNamedBadgeCount,
    ll.AllBadgeNames,
    ll.MaxAcceptedAnswerScore,
    ll.OverallUserRank,
    q.QuestionId,
    qs.IsReopenedAfterClose,
    qs.ClosingTypeName,
    CASE 
        WHEN qs.IsReopenedAfterClose = 1 THEN 'REOPENED RECENTLY' 
        ELSE 'CLOSED' 
    END AS CloseStatus,
    CASE 
        WHEN ll.TotalPostScore > 50 THEN substring(ll.AllBadgeNames from 1 for 15) || '...' ELSE ll.AllBadgeNames 
    END AS ShortBadgeList
FROM CombinedLeadboard ll
LEFT JOIN RecentClosedQuestions qs ON qs.OwnerUserId = ll.UserId
WHERE ll.OverallUserRank <= 100
ORDER BY ll.OverallUserRank, qs.ClosedDate DESC NULLS LAST
LIMIT 100;