-- {"query": "45085.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 194990, "output_tokens": 34318} 
WITH UserTagExpertise AS (
    SELECT 
        u.Id AS UserId, 
        t.TagName, 
        COUNT(DISTINCT p.Id) AS AnswerCount,
        AVG(p.Score) AS AvgAnswerScore,
        SUM(v.VoteTypeId = 2) AS UpVotes,
        SUM(v.VoteTypeId = 3) AS DownVotes
    FROM 
        Users u
        JOIN Posts p ON u.Id = p.OwnerUserId
        JOIN Tags t ON string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') @> ARRAY[t.TagName]
    WHERE 
        p.PostTypeId = 2
    GROUP BY 
        u.Id, t.TagName
    HAVING 
        COUNT(DISTINCT p.Id) > 10
),
TagPopularityRanking AS (
    SELECT 
        TagName, 
        DENSE_RANK() OVER (ORDER BY AvgAnswerScore DESC) AS ScoreRank,
        DENSE_RANK() OVER (ORDER BY AnswerCount DESC) AS ActivityRank
    FROM 
        UserTagExpertise
    WHERE 
        UpVotes > DownVotes
)
SELECT 
    ute.UserId,
    ute.TagName,
    ute.AnswerCount,
    ute.AvgAnswerScore,
    tpr.ScoreRank,
    tpr.ActivityRank
FROM 
    UserTagExpertise ute
JOIN 
    TagPopularityRanking tpr ON ute.TagName = tpr.TagName
WHERE 
    tpr.ScoreRank <= 50 AND 
    tpr.ActivityRank <= 50
ORDER BY 
    ute.AvgAnswerScore DESC, 
    ute.AnswerCount DESC
LIMIT 1000;