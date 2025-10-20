-- {"query": "50022.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1022} 
WITH TopTags AS (
    -- Find the 5 most frequently used tags
    SELECT TagName
    FROM Tags
    ORDER BY Count DESC
    LIMIT 5
),
UserTagActivity AS (
    -- For each user and each top tag, calculate their activity metrics
    SELECT
        p_a.OwnerUserId,
        tt.TagName,
        COUNT(p_a.Id) AS AnswersInTag,
        AVG(p_a.Score) AS AvgScoreInTag,
        SUM(p_a.Score) AS TotalScoreInTag,
        (SELECT COUNT(*) FROM Posts p_inner WHERE p_inner.OwnerUserId = p_a.OwnerUserId AND p_inner.PostTypeId = 2) AS TotalUserAnswers
    FROM Posts p_a -- Answers
    JOIN Posts p_q ON p_a.ParentId = p_q.Id -- Questions they belong to
    JOIN TopTags tt ON p_q.Tags LIKE '%' || tt.TagName || '%'
    WHERE
        p_a.PostTypeId = 2 AND p_a.OwnerUserId IS NOT NULL
    GROUP BY
        p_a.OwnerUserId, tt.TagName
    HAVING
        COUNT(p_a.Id) > 10 AND AVG(p_a.Score) > 5 -- Filter for users with significant and quality contributions
),
RankedSpecialists AS (
    -- Rank users within each tag based on a "specialization score"
    -- The score prioritizes a high concentration of answers in a tag combined with a high average score.
    SELECT
        uta.OwnerUserId,
        uta.TagName,
        uta.AnswersInTag,
        uta.AvgScoreInTag,
        (CAST(uta.AnswersInTag AS REAL) / uta.TotalUserAnswers) * uta.AvgScoreInTag AS SpecializationScore,
        ROW_NUMBER() OVER(PARTITION BY uta.TagName ORDER BY (CAST(uta.AnswersInTag AS REAL) / uta.TotalUserAnswers) * uta.AvgScoreInTag DESC) AS SpecialistRank
    FROM UserTagActivity uta
    WHERE uta.TotalUserAnswers > 20 -- Only consider users with a reasonable total answer count
),
SpecialistBestAnswer AS (
    -- For each top specialist, find their highest-scoring answer within their specialized tag
    SELECT
        rs.OwnerUserId,
        rs.TagName,
        p_a.Id AS BestAnswerId,
        p_q.Id AS QuestionId,
        p_q.Title AS QuestionTitle,
        p_a.Score AS BestAnswerScore,
        p_a.CreationDate AS BestAnswerDate,
        ROW_NUMBER() OVER(PARTITION BY rs.OwnerUserId, rs.TagName ORDER BY p_a.Score DESC, p_a.CreationDate DESC) AS AnswerRank
    FROM Posts p_a
    JOIN Posts p_q ON p_a.ParentId = p_q.Id
    JOIN RankedSpecialists rs ON p_a.OwnerUserId = rs.OwnerUserId AND p_q.Tags LIKE '%' || rs.TagName || '%'
    WHERE rs.SpecialistRank <= 5 AND p_a.PostTypeId = 2
)
-- Final result: Combine all information to present a profile of top specialists for top tags
SELECT
    rs.TagName AS "Specialty_Tag",
    rs.SpecialistRank AS "Rank_in_Tag",
    u.DisplayName AS "Specialist_Name",
    u.Reputation,
    u.CreationDate AS "User_Since",
    rs.SpecializationScore,
    rs.AnswersInTag,
    rs.AvgScoreInTag,
    sba.QuestionTitle AS "Top_Answered_Question",
    sba.BestAnswerScore AS "Top_Answer_Score",
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = sba.BestAnswerId) AS "Comments_on_Top_Answer",
    (SELECT STRING_AGG(b.Name, ', ') FROM (SELECT Name FROM Badges WHERE UserId = u.Id AND Class = 1 ORDER BY Date DESC LIMIT 3) b) AS "Recent_Gold_Badges"
FROM RankedSpecialists rs
JOIN Users u ON rs.OwnerUserId = u.Id
JOIN SpecialistBestAnswer sba ON rs.OwnerUserId = sba.OwnerUserId AND rs.TagName = sba.TagName
WHERE
    rs.SpecialistRank <= 5 AND sba.AnswerRank = 1
ORDER BY
    rs.TagName,
    rs.SpecialistRank;