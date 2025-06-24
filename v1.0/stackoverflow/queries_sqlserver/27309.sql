
WITH RankedUserPosts AS (
    SELECT 
        p.OwnerUserId,
        COUNT(*) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS UserRank
    FROM Posts p
    GROUP BY p.OwnerUserId
),
TopUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, r.TotalPosts, r.QuestionCount, r.AnswerCount
    FROM Users u
    JOIN RankedUserPosts r ON u.Id = r.OwnerUserId
    WHERE r.UserRank <= 10  
),
PostTagCounts AS (
    SELECT
        p.Id AS PostId,
        t.TagName,
        COUNT(*) AS TagCount
    FROM Posts p
    CROSS APPLY (SELECT value AS TagName
                 FROM STRING_SPLIT(SUBSTRING(p.Tags, 2, LEN(p.Tags) - 2), '><')) AS t
    GROUP BY p.Id, t.TagName
),
TopTags AS (
    SELECT 
        TagName,
        SUM(TagCount) AS TotalTagCount
    FROM PostTagCounts
    GROUP BY TagName
    ORDER BY TotalTagCount DESC
    OFFSET 0 ROWS FETCH NEXT 5 ROWS ONLY  
)
SELECT 
    tu.DisplayName,
    tu.Reputation,
    tu.TotalPosts,
    tu.QuestionCount,
    tu.AnswerCount,
    tg.TagName,
    tg.TotalTagCount
FROM TopUsers tu
JOIN TopTags tg ON tg.TagName IN (SELECT value FROM STRING_SPLIT(tg.TagName, ' '))
ORDER BY tu.Reputation DESC, tg.TotalTagCount DESC;
