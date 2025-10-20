-- {"query": "32072.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 513} 

WITH RecentQuestions AS (
    SELECT 
        Posts.Id AS QuestionId,
        Posts.Title,
        Posts.CreationDate AS QuestionCreation,
        COALESCE(Posts.Score, 0) AS QuestionScore,
        COALESCE(SUM(CASE WHEN VoteTypes.Id = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
        COALESCE(SUM(CASE WHEN VoteTypes.Id = 3 THEN 1 ELSE 0 END), 0) AS DownVotes,
        COUNT(DISTINCT Comments.Id) AS TotalComments
    FROM 
        Posts
    LEFT JOIN 
        Votes ON Posts.Id = Votes.PostId
    LEFT JOIN 
        VoteTypes ON Votes.VoteTypeId = VoteTypes.Id
    LEFT JOIN 
        Comments ON Posts.Id = Comments.PostId
    WHERE 
        Posts.PostTypeId = 1 
        AND Posts.CreationDate >= NOW() - INTERVAL '30 days'
    GROUP BY 
        Posts.Id, Posts.Title, Posts.CreationDate, Posts.Score
    HAVING 
        COUNT(DISTINCT Comments.Id) > 0
),
ActiveUsers AS (
    SELECT 
        Users.Id AS UserId,
        Users.DisplayName,
        COALESCE(SUM(Posts.Score), 0) AS TotalPostScore,
        COUNT(DISTINCT Badges.Id) AS BadgeCount
    FROM 
        Users
    LEFT JOIN 
        Posts ON Users.Id = Posts.OwnerUserId
    LEFT JOIN 
        Badges ON Users.Id = Badges.UserId
    WHERE 
        Users.CreationDate <= NOW() - INTERVAL '90 days'
        AND Users.LastAccessDate >= NOW() - INTERVAL '30 days'
    GROUP BY 
        Users.Id, Users.DisplayName
    HAVING 
        COUNT(DISTINCT Posts.Id) > 0 
        AND COUNT(DISTINCT Badges.Id) > 0
)
SELECT 
    Q.QuestionId,
    Q.Title,
    Q.QuestionCreation,
    Q.QuestionScore,
    Q.UpVotes,
    Q.DownVotes,
    Q.TotalComments,
    U.UserId,
    U.DisplayName,
    U.TotalPostScore,
    U.BadgeCount
FROM 
    RecentQuestions Q
JOIN 
    ActiveUsers U ON Q.QuestionId = (SELECT Posts.Id FROM Posts WHERE Posts.OwnerUserId = U.UserId LIMIT 1)
ORDER BY 
    Q.QuestionCreation DESC, U.BadgeCount DESC;
