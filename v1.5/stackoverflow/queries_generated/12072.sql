-- {"query": "12072.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 975} 

WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate) AS PostRank,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) OVER (PARTITION BY p.Id) AS UpVotes,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) OVER (PARTITION BY p.Id) AS DownVotes,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCount
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    WHERE 
        p.PostTypeId IN (1, 2)
),
TopPosts AS (
    SELECT 
        Id, 
        Title, 
        Score, 
        ViewCount, 
        CreationDate, 
        OwnerDisplayName, 
        PostRank, 
        UpVotes, 
        DownVotes, 
        CommentCount
    FROM 
        RankedPosts
    WHERE 
        PostRank <= 10
),
UserActivity AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsAsked,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersGiven,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Votes v ON u.Id = v.UserId
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation
),
ActiveUsers AS (
    SELECT 
        Id, 
        DisplayName, 
        Reputation, 
        QuestionsAsked, 
        AnswersGiven, 
        UpVotesReceived, 
        DownVotesReceived,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, QuestionsAsked DESC, AnswersGiven DESC) AS UserRank
    FROM 
        UserActivity
    WHERE 
        Reputation > 1000
),
TagStats AS (
    SELECT 
        t.TagName,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgScore,
        SUM(p.ViewCount) AS TotalViews
    FROM 
        Tags t
    JOIN 
        Posts p ON t.Id = ANY(string_to_array(p.Tags, ''><''))
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        t.TagName
),
TopTags AS (
    SELECT 
        TagName, 
        PostCount, 
        AvgScore, 
        TotalViews
    FROM 
        TagStats
    ORDER BY 
        PostCount DESC, 
        AvgScore DESC, 
        TotalViews DESC
    LIMIT 20
)
SELECT 
    tp.Title AS TopPostTitle, 
    tp.Score AS TopPostScore, 
    tp.ViewCount AS TopPostViews, 
    tp.CreationDate AS TopPostCreationDate, 
    tp.OwnerDisplayName AS TopPostOwner, 
    au.DisplayName AS ActiveUserDisplayName, 
    au.Reputation AS ActiveUserReputation, 
    au.QuestionsAsked, 
    au.AnswersGiven, 
    au.UpVotesReceived, 
    au.DownVotesReceived, 
    tt.TagName, 
    tt.PostCount, 
    tt.AvgScore, 
    tt.TotalViews
FROM 
    TopPosts tp
JOIN 
    ActiveUsers au ON tp.OwnerDisplayName = au.DisplayName
JOIN 
    TopTags tt ON tp.Tags LIKE '%' || tt.TagName || '%'
ORDER BY 
    tp.Score DESC, 
    au.Reputation DESC, 
    tt.PostCount DESC;
