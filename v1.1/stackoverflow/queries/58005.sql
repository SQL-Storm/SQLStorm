WITH ActiveUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, COUNT(b.Id) AS GoldBadges
    FROM Users u
    JOIN Badges b ON u.Id = b.UserId AND b.Class = 1
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(b.Id) >= 5
), PostStats AS (
    SELECT p.OwnerUserId, 
           COUNT(DISTINCT p.Id) AS TotalQuestions,
           COUNT(DISTINCT p.AcceptedAnswerId) AS AcceptedAnswers,
           AVG(p.Score) AS AvgScore,
           SUM(p.ViewCount) AS TotalViews
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.CreationDate BETWEEN DATE '2020-01-01' AND DATE '2023-01-01'
    GROUP BY p.OwnerUserId
), VoteAnalysis AS (
    SELECT v.PostId, 
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
           COUNT(DISTINCT v.UserId) AS UniqueVoters
    FROM Votes v
    GROUP BY v.PostId
), PostHistoryEdits AS (
    SELECT ph.PostId, 
           COUNT(ph.Id) AS EditCount,
           STRING_AGG(DISTINCT ph.Text, '; ') AS EditReasons
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 5
    GROUP BY ph.PostId
    HAVING COUNT(ph.Id) > 3
)
SELECT au.DisplayName,
       au.Reputation,
       au.GoldBadges,
       ps.TotalQuestions,
       ps.AcceptedAnswers,
       ps.AvgScore,
       ps.TotalViews,
       RANK() OVER (ORDER BY ps.TotalViews DESC) AS ViewRank,
       va.Upvotes,
       va.Downvotes,
       (va.Upvotes - va.Downvotes) AS NetVotes,
       phe.EditCount,
       phe.EditReasons,
       (SELECT COUNT(*) 
        FROM Comments c 
        WHERE c.PostId IN (SELECT p2.Id FROM Posts p2 WHERE p2.OwnerUserId = au.Id)
       ) AS TotalComments,
       (SELECT STRING_AGG(DISTINCT t.TagName, ', ')
        FROM (
            SELECT TRIM(tag) AS TagName
            FROM Posts p3
            CROSS JOIN LATERAL (
              SELECT unnest(string_to_array(substring(p3.Tags FROM 2 FOR (char_length(p3.Tags) - 2)), '><')) AS tag
            ) s
            WHERE p3.OwnerUserId = au.Id
       ) t
       ) AS FrequentTags
FROM ActiveUsers au
JOIN PostStats ps ON au.Id = ps.OwnerUserId
JOIN Posts p ON au.Id = p.OwnerUserId
JOIN VoteAnalysis va ON p.Id = va.PostId
JOIN PostHistoryEdits phe ON p.Id = phe.PostId
WHERE ps.AcceptedAnswers > ps.TotalQuestions * 0.5
GROUP BY au.DisplayName,
         au.Reputation,
         au.GoldBadges,
         ps.TotalQuestions,
         ps.AcceptedAnswers,
         ps.AvgScore,
         ps.TotalViews,
         va.Upvotes,
         va.Downvotes,
         phe.EditCount,
         phe.EditReasons,
         au.Id
ORDER BY au.Reputation DESC, ps.TotalViews DESC, NetVotes DESC
LIMIT 100;