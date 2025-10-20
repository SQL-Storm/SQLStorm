-- {"query": "54093.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1845} 
WITH user_stats AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswersPosted,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 END),0) AS TotalUpVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 END),0) AS TotalDownVotes,
        COALESCE(SUM(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 END),0) AS TotalEdits,
        COALESCE(SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 END),0) AS DuplicateLinks,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 END),0) AS AcceptedAnswers
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.UserId = u.Id
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id
    GROUP BY u.Id, u.Reputation, u.DisplayName
),
badge_counts AS (
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 END) AS Gold,
        SUM(CASE WHEN Class = 2 THEN 1 END) AS Silver,
        SUM(CASE WHEN Class = 3 THEN 1 END) AS Bronze
    FROM Badges
    GROUP BY UserId
),
ranking AS (
    SELECT
        us.UserId,
        us.Reputation,
        us.DisplayName,
        us.QuestionsPosted,
        us.AnswersPosted,
        us.TotalUpVotes,
        us.TotalDownVotes,
        us.TotalEdits,
        us.DuplicateLinks,
        us.AcceptedAnswers,
        COALESCE(bc.Gold,0) AS GoldBadges,
        COALESCE(bc.Silver,0) AS SilverBadges,
        COALESCE(bc.Bronze,0) AS BronzeBadges,
        RANK() OVER (ORDER BY us.TotalUpVotes DESC, us.Reputation ASC) AS Rank
    FROM user_stats us
    LEFT JOIN badge_counts bc ON bc.UserId = us.UserId
    WHERE (us.QuestionsPosted + us.AnswersPosted) > 500
      AND us.TotalUpVotes > 1000
)
SELECT *
FROM ranking
WHERE Rank <= 20
ORDER BY Rank, Reputation DESC;