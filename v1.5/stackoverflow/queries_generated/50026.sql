-- {"query": "50026.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1210} 

WITH PopularTags AS (
    SELECT
        TagName,
        Id
    FROM Tags
    ORDER BY Count DESC
    LIMIT 50
), UserTagActivity AS (
    SELECT
        p.OwnerUserId,
        t.TagName,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COALESCE(AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END), 0) AS AvgAnswerScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS TotalAnswerScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount
    FROM Posts AS p
    JOIN PopularTags AS t ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    WHERE
        p.OwnerUserId IS NOT NULL
        AND p.PostTypeId IN (1, 2)
    GROUP BY
        p.OwnerUserId,
        t.TagName
    HAVING COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 10
), QuestionStats AS (
    SELECT
        q.OwnerUserId,
        AVG(EXTRACT(EPOCH FROM (first_comment.CreationDate - q.CreationDate))) AS AvgTimeToFirstComment,
        AVG(EXTRACT(EPOCH FROM (first_answer.CreationDate - q.CreationDate))) AS AvgTimeToFirstAnswer,
        AVG(EXTRACT(EPOCH FROM (accepted_answer.CreationDate - q.CreationDate))) AS AvgTimeToAcceptedAnswer,
        COUNT(q.AcceptedAnswerId)::decimal / NULLIF(COUNT(q.Id), 0) AS PctQuestionsWithAcceptedAnswer
    FROM Posts AS q
    LEFT JOIN LATERAL (
        SELECT MIN(c.CreationDate) as CreationDate
        FROM Comments AS c
        WHERE c.PostId = q.Id AND c.UserId != q.OwnerUserId
    ) first_comment ON true
    LEFT JOIN LATERAL (
        SELECT MIN(a.CreationDate) as CreationDate
        FROM Posts AS a
        WHERE a.ParentId = q.Id AND a.OwnerUserId != q.OwnerUserId
    ) first_answer ON true
    LEFT JOIN Posts AS accepted_answer ON q.AcceptedAnswerId = accepted_answer.Id
    WHERE q.PostTypeId = 1 AND q.OwnerUserId IS NOT NULL
    GROUP BY q.OwnerUserId
), UserProfile AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.UpVotes AS TotalUpvotesReceived,
        u.DownVotes AS TotalDownvotesReceived,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGiven
    FROM Users AS u
    LEFT JOIN Badges AS b ON u.Id = b.UserId
    LEFT JOIN Votes AS v ON u.Id = v.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.UpVotes, u.DownVotes
)
SELECT
    up.DisplayName,
    up.Reputation,
    uta.TagName AS SpecialistTag,
    uta.AnswerCount,
    uta.QuestionCount,
    ROUND(uta.AvgAnswerScore, 2) AS AvgAnswerScore,
    (uta.TotalAnswerScore * (1 + (uta.AnswerCount::decimal / NULLIF(uta.QuestionCount, 0)))) / (1 + EXTRACT(EPOCH FROM (NOW() - up.UserCreationDate))/3600/24/365) AS SpecialistScore,
    ROUND(qs.AvgTimeToFirstAnswer / 3600, 2) AS AvgHoursToFirstAnswer,
    ROUND(qs.AvgTimeToAcceptedAnswer / 3600, 2) AS AvgHoursToAcceptedAnswer,
    ROUND(qs.PctQuestionsWithAcceptedAnswer * 100, 2) AS PctAccepted,
    up.UpvotesGiven,
    up.DownvotesGiven,
    RANK() OVER (PARTITION BY uta.TagName ORDER BY (uta.TotalAnswerScore * (1 + (uta.AnswerCount::decimal / NULLIF(uta.QuestionCount, 0)))) / (1 + EXTRACT(EPOCH FROM (NOW() - up.UserCreationDate))/3600/24/365) DESC) AS RankInTag
FROM UserTagActivity AS uta
JOIN UserProfile AS up ON uta.OwnerUserId = up.Id
JOIN QuestionStats AS qs ON uta.OwnerUserId = qs.OwnerUserId
WHERE EXISTS (
    SELECT 1
    FROM Badges AS b
    WHERE b.UserId = uta.OwnerUserId
      AND b.Name = uta.TagName
      AND b.Class = 1
      AND b.TagBased = true
)
AND uta.AvgAnswerScore > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2)
ORDER BY
    SpecialistTag,
    RankInTag
LIMIT 200;
