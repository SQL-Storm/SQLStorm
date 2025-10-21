WITH UserTagExpertise AS (
    SELECT 
        u.Id AS UserId, 
        t.TagName, 
        COUNT(DISTINCT p.Id) AS AnswerCount,
        AVG(p.Score) AS AvgAnswerScore,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM 
        Users AS u
        JOIN Posts AS p ON u.Id = p.OwnerUserId
        JOIN Tags AS t ON
            POSITION(t.TagName IN SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2)) > 0
        LEFT JOIN Votes v ON p.Id = v.PostId
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
        ROW_NUMBER() OVER (ORDER BY AvgAnswerScore DESC) AS ScoreRank,
        ROW_NUMBER() OVER (ORDER BY AnswerCount DESC) AS ActivityRank
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
    UserTagExpertise AS ute
JOIN 
    TagPopularityRanking AS tpr ON ute.TagName = tpr.TagName
WHERE 
    tpr.ScoreRank <= 50 AND 
    tpr.ActivityRank <= 50
ORDER BY 
    ute.AvgAnswerScore DESC, 
    ute.AnswerCount DESC
LIMIT 1000;