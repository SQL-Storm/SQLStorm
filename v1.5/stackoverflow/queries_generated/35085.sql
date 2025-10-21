-- {"query": "35085.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 797} 
WITH top_users AS (
    SELECT u.Id AS UserId, u.DisplayName, u.Reputation, COUNT(p.Id) AS TotalPosts, SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions, SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(p.Id) > 50
    ORDER BY Reputation DESC
    LIMIT 100
),
user_badges AS (
    SELECT b.UserId, COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges, COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges, COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Badges b
    WHERE b.Date >= NOW() - INTERVAL '1 year'
      AND b.UserId IN (SELECT UserId FROM top_users)
    GROUP BY b.UserId
),
user_votes AS (
    SELECT p.OwnerUserId AS UserId,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes v
    JOIN Posts p ON v.PostId = p.Id
    WHERE p.OwnerUserId IN (SELECT UserId FROM top_users)
      AND v.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY p.OwnerUserId
),
avg_answer_time AS (
    SELECT q.OwnerUserId AS UserId,
           AVG(EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/60) AS AvgAnswerTimeMinutes
    FROM Posts q
    JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
      AND q.OwnerUserId IN (SELECT UserId FROM top_users)
      AND a.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY q.OwnerUserId
),
edit_stats AS (
    SELECT ph.UserId, COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS EditsMade
    FROM PostHistory ph
    WHERE ph.UserId IN (SELECT UserId FROM top_users)
      AND ph.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY ph.UserId
)
SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.TotalPosts,
    tu.Questions,
    tu.Answers,
    COALESCE(ub.GoldBadges,0) AS GoldBadges,
    COALESCE(ub.SilverBadges,0) AS SilverBadges,
    COALESCE(ub.BronzeBadges,0) AS BronzeBadges,
    COALESCE(uv.UpVotes,0) AS TotalUpVotes,
    COALESCE(uv.DownVotes,0) AS TotalDownVotes,
    COALESCE(aat.AvgAnswerTimeMinutes, NULL) AS AvgAnswerTimeMinutes,
    COALESCE(es.EditsMade,0) AS EditsMade
FROM top_users tu
LEFT JOIN user_badges ub ON tu.UserId = ub.UserId
LEFT JOIN user_votes uv ON tu.UserId = uv.UserId
LEFT JOIN avg_answer_time aat ON tu.UserId = aat.UserId
LEFT JOIN edit_stats es ON tu.UserId = es.UserId
ORDER BY tu.Reputation DESC, tu.TotalPosts DESC;