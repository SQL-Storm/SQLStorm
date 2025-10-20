WITH UserTagExpertise AS (
    SELECT 
        u.Id AS UserId, 
        t.TagName, 
        COUNT(DISTINCT p.Id) AS AnswerCount,
        AVG(p.Score) AS AvgAnswerScore,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM 
        Users u
        JOIN Posts p ON u.Id = p.OwnerUserId
        JOIN Tags t ON EXISTS (
            SELECT 1
            FROM unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tagname(tag)
            WHERE tag = t.TagName
        )
        LEFT JOIN Votes v ON v.PostId = p.Id
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
GROUP BY
    ute.UserId,
    ute.TagName,
    ute.AnswerCount,
    ute.AvgAnswerScore,
    tpr.ScoreRank,
    tpr.ActivityRank
ORDER BY 
    ute.AvgAnswerScore DESC, 
    ute.AnswerCount DESC
LIMIT 1000;