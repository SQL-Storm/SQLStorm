-- {"query": "1044.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 632} 

WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        MAX(p.LastActivityDate) AS LastActive
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    GROUP BY 
        u.Id
),
TopTags AS (
    SELECT 
        unnest(string_to_array(Tags, '><')) AS TagName,
        COUNT(*) AS TagCount
    FROM 
        Posts
    WHERE 
        PostTypeId = 1
    GROUP BY 
        TagName
    ORDER BY 
        TagCount DESC
    LIMIT 10
),
PostVoteStats AS (
    SELECT 
        p.Id AS PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes
    FROM 
        Posts p
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    GROUP BY 
        p.Id
),
RankedPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        COALESCE(vs.UpVotes, 0) AS UpVotes,
        COALESCE(vs.DownVotes, 0) AS DownVotes,
        RANK() OVER (ORDER BY p.Score DESC, (COALESCE(vs.UpVotes, 0) - COALESCE(vs.DownVotes, 0)) DESC) AS Rank
    FROM 
        Posts p
    LEFT JOIN 
        PostVoteStats vs ON p.Id = vs.PostId
),
FinalStats AS (
    SELECT 
        u.UserId,
        u.DisplayName,
        u.TotalPosts,
        u.TotalQuestions,
        u.TotalAnswers,
        t.TagName,
        p.Id AS PostId,
        p.Title,
        p.Rank,
        p.Score
    FROM 
        UserStats u
    JOIN 
        TopTags t ON u.TotalPosts > 0
    JOIN 
        RankedPosts p ON u.TotalPosts = p.Rank
)
SELECT 
    fs.DisplayName,
    fs.TagName,
    fs.Title,
    fs.Score,
    fs.Rank,
    fs.TotalQuestions,
    fs.TotalAnswers,
    CASE 
        WHEN fs.TotalQuestions > fs.TotalAnswers THEN 'More Questions' 
        ELSE 'More Answers' 
    END AS QuestionAnswerBalance,
    COALESCE(ROUND((fs.TotalAnswers::float / NULLIF(fs.TotalQuestions, 0) * 100), 2), 0) AS AnswerToQuestionRatio
FROM 
    FinalStats fs
WHERE 
    fs.Rank <= 10 
ORDER BY 
    fs.Rank;
