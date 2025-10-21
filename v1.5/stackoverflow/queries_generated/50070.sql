-- {"query": "50070.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1188} 

WITH PopularTags AS (
    -- Step 1: Identify the 100 most frequently used tags. These represent the most popular topics.
    SELECT
        TagName,
        Id
    FROM Tags
    ORDER BY Count DESC
    LIMIT 100
),
ExpertCandidates AS (
    -- Step 2: Find users who are active in these popular tags, focusing on those who provide answers.
    -- This CTE aggregates key metrics for each user within each popular tag.
    SELECT
        p_ans.OwnerUserId,
        pt.TagName,
        COUNT(p_ans.Id) AS TotalAnswers,
        SUM(p_ans.Score) AS TotalAnswerScore,
        SUM(CASE WHEN p_q.AcceptedAnswerId = p_ans.Id THEN 1 ELSE 0 END) AS AcceptedAnswers,
        AVG(p_ans.Score) AS AvgAnswerScore,
        MIN(p_ans.CreationDate) AS FirstAnswerDate,
        MAX(p_ans.CreationDate) AS LastAnswerDate
    FROM Posts AS p_ans -- Answers
    JOIN Posts AS p_q ON p_ans.ParentId = p_q.Id -- The Question for the Answer
    JOIN PopularTags AS pt ON p_q.Tags LIKE '%' || '<' || pt.TagName || '>' || '%'
    WHERE p_ans.PostTypeId = 2 -- 2 = Answer
      AND p_ans.OwnerUserId IS NOT NULL
    GROUP BY
        p_ans.OwnerUserId,
        pt.TagName
    HAVING COUNT(p_ans.Id) > 5 -- Filter for users with a minimum of 5 answers in the tag
),
UserContributionScore AS (
    -- Step 3: Calculate a composite "Contribution Score" for each user in each tag,
    -- and rank them to find the top experts.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        ec.TagName,
        ec.TotalAnswers,
        ec.TotalAnswerScore,
        ec.AcceptedAnswers,
        -- Calculate a score based on various contributions. Accepted answers and high-score answers are weighted more heavily.
        -- We also add points for Gold/Silver tag-specific badges.
        (ec.TotalAnswerScore * 0.5) + (ec.AcceptedAnswers * 25) +
        (SELECT
            SUM(CASE b.Class WHEN 1 THEN 100 WHEN 2 THEN 50 ELSE 0 END)
         FROM Badges b
         WHERE b.UserId = ec.OwnerUserId AND b.TagBased = '1' AND b.Name = ec.TagName
        ) AS ContributionScore,
        -- Use a window function to rank users within each tag based on their score and reputation.
        DENSE_RANK() OVER (PARTITION BY ec.TagName ORDER BY
            (ec.TotalAnswerScore * 0.5) + (ec.AcceptedAnswers * 25) +
            COALESCE((SELECT
                SUM(CASE b.Class WHEN 1 THEN 100 WHEN 2 THEN 50 ELSE 0 END)
             FROM Badges b
             WHERE b.UserId = ec.OwnerUserId AND b.TagBased = '1' AND b.Name = ec.TagName
            ), 0) DESC,
            u.Reputation DESC
        ) AS ExpertRank
    FROM ExpertCandidates ec
    JOIN Users u ON ec.OwnerUserId = u.Id
    WHERE u.Reputation > 1000 -- Consider only users with a certain reputation threshold
)
-- Final Step: Select the top 3 experts for each popular tag and join with additional information
-- about the tag's lifecycle and the user's activity.
SELECT
    ucs.TagName,
    ucs.ExpertRank,
    ucs.DisplayName AS ExpertDisplayName,
    ucs.Reputation AS ExpertReputation,
    ucs.ContributionScore,
    ucs.TotalAnswers,
    ucs.TotalAnswerScore,
    ucs.AcceptedAnswers,
    (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || '<' || ucs.TagName || '>' || '%' AND p.PostTypeId = 1) AS QuestionsInTag,
    -- Correlated subquery to find the title of the highest-voted question the user answered in that tag.
    (SELECT p_q.Title
     FROM Posts p_a
     JOIN Posts p_q ON p_a.ParentId = p_q.Id
     WHERE p_a.OwnerUserId = ucs.UserId AND p_q.Tags LIKE '%' || '<' || ucs.TagName || '>' || '%'
     ORDER BY p_a.Score DESC
     LIMIT 1
    ) AS TopAnsweredQuestionTitle,
    -- Correlated subquery to find the number of comments the user made on questions in that tag.
    (SELECT COUNT(c.Id)
     FROM Comments c
     JOIN Posts p ON c.PostId = p.Id
     WHERE c.UserId = ucs.UserId AND p.Tags LIKE '%' || '<' || ucs.TagName || '>' || '%' AND p.PostTypeId = 1
    ) AS CommentsOnQuestions
FROM UserContributionScore ucs
WHERE ucs.ExpertRank <= 3
ORDER BY
    ucs.TagName,
    ucs.ExpertRank;
