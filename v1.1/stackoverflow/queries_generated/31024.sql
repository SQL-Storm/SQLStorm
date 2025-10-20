-- {"query": "31024.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 506} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(v.VoteTypeId = 2) AS UpVotes,
        SUM(v.VoteTypeId = 3) AS DownVotes,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS Rank
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId AND v.UserId = u.Id
    LEFT JOIN 
        Badges b ON b.UserId = u.Id
    GROUP BY 
        u.Id
),
TopActiveUsers AS (
    SELECT 
        UserId,
        DisplayName,
        PostCount,
        QuestionCount,
        AnswerCount,
        UpVotes,
        DownVotes,
        GoldBadges,
        SilverBadges,
        BronzeBadges,
        Rank
    FROM 
        UserActivity
    WHERE 
        Rank <= 10
)
SELECT 
    t.UserId,
    t.DisplayName,
    t.PostCount,
    t.QuestionCount,
    t.AnswerCount,
    t.UpVotes,
    t.DownVotes,
    t.GoldBadges,
    t.SilverBadges,
    t.BronzeBadges,
    COALESCE(SUM(p.ViewCount), 0) AS TotalViewCount
FROM 
    TopActiveUsers t
LEFT JOIN 
    Posts p ON t.UserId = p.OwnerUserId
GROUP BY 
    t.UserId, t.DisplayName, t.PostCount, t.QuestionCount, t.AnswerCount, t.UpVotes, t.DownVotes, t.GoldBadges, t.SilverBadges, t.BronzeBadges
ORDER BY 
    t.Rank;
