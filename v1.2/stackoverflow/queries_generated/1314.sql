-- {"query": "1314.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1318} 
with RecursiveUserBadgeCTE as (
    select 
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        b.Date,
        row_number() over (partition by u.Id order by b.Date desc, b.Class) as BadgeRank
    from Users u
    left join Badges b on b.UserId = u.Id
    where u.Reputation > 1000
),
LatestBadges peruser as (
    select 
        UserId,
        DisplayName,
        BadgeName,
        Class,
        Date
    from RecursiveUserBadgeCTE
    where BadgeRank <= 3
),
-- Fetch top scoring QA pairs with window functions and complicated predicates
TopQAPairs as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.Score as QuestionScore,
        q.ViewCount,
        ans.Id as AnswerId,
        ans.Score as AnswerScore,
        coalesce(ans.OwnerUserId, -1) as AnswererId,
        u.DisplayName as AnswererName,
        max(vt.Name) over (partition by ans.Id) as MaxVoteType_OnAnswer,
        count(distinct c.Id) over (partition by q.Id) as QuestionCommentCount,
        -- boolean complicated pred: whether question is closed recently (<90 days from last activity)
        case when q.ClosedDate is not null and q.ClosedDate > (q.LastActivityDate - interval '90 days') then 1 else 0 end as IsRecentlyClosed,
        row_number() over (partition by q.Id order by ans.Score desc, ans.CreationDate asc) as AnswerRank
    from Posts q
    join Posts ans on ans.ParentId = q.Id and ans.PostTypeId = 2
    left join Votes v on v.PostId = ans.Id
    left join VoteTypes vt on vt.Id = v.VoteTypeId
    left join Comments c on c.PostId = q.Id
    left join Users u on u.Id = ans.OwnerUserId
    where q.PostTypeId = 1
),
-- Their accepted answers & aggregate voting info
AcceptedAnswerAgg as (
    select 
        q.Id as QuestionId,
        q.AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        coalesce(u.DisplayName,'[deleted]') as AcceptedAnswerer,
        (select count(*) from Votes v where v.PostId = q.AcceptedAnswerId and v.VoteTypeId = 2) as AcceptedAnswerUpvoteCount,
        (select count(*) from Votes v where v.PostId = q.AcceptedAnswerId and v.VoteTypeId = 3) as AcceptedAnswerDownvoteCount
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
-- Combine all with some outer joins, filtering for questions with at least 2 answers
Combined as (
    select 
        tq.QuestionId,
        tq.Title,
        tq.Tags,
        tq.QuestionScore,
        tq.ViewCount,
        aagg.AcceptedAnswerId,
        aagg.AcceptedAnswerScore,
        aagg.AcceptedAnswerer,
        aagg.AcceptedAnswerUpvoteCount,
        aagg.AcceptedAnswerDownvoteCount,
        tq.AnswerId,
        tq.AnswerScore,
        tq.AnswererId,
        tq.AnswererName,
        tq.MaxVoteType_OnAnswer,
        tq.QuestionCommentCount,
        tq.IsRecentlyClosed
    from TopQAPairs tq
    left join AcceptedAnswerAgg aagg on aagg.QuestionId = tq.QuestionId
    where tq.AnswerRank = 1
),
-- Aggregate badges per answerer
BadgeCounts as (
    select 
        u.Id as UserId,
        count(distinct b.Id) as BadgeCount,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id
),
-- PostLinks info about how many duplicates a question has
DuplicateCounts as (
    select pl.PostId, count(*) as DuplicateOfCount
    from PostLinks pl
    where pl.LinkTypeId = 3
    group by pl.PostId
),
-- Final combined query with hopes to measure complex load
Final as (
    select 
        c.QuestionId,
        c.Title,
        left(c.Tags, 50) as SampledTags,
        c.QuestionScore,
        c.ViewCount,
        coalesce(dc.DuplicateOfCount, 0) as DuplicateHowMany,
        c.AcceptedAnswerId,
        c.AcceptedAnswerScore,
        c.AcceptedAnswerer,
        c.AcceptedAnswerUpvoteCount,
        c.AcceptedAnswerDownvoteCount,
        c.AnswerId,
        c.AnswerScore,
        c.AnswererId,
        c.AnswererName,
        b.BadgeCount,
        b.GoldBadges,
        b.SilverBadges,
        b.BronzeBadges,
        c.MaxVoteType_OnAnswer,
        c.QuestionCommentCount,
        c.IsRecentlyClosed,
        -- Complex NULL logic and string expressions to classify question recency and popularity
        case 
            when c.LastActivityDate > current_date - interval '30 days' and c.QuestionScore > 10 then 'Hot & Recent'
            when c.ClosedDate is not null then 'Closed Question'
            when c.ViewCount > 10000 then 'Popular Question'
            else 'Normal'
        end as QuestionClass
    from Combined c
    left join DuplicateCounts dc on dc.PostId = c.QuestionId
    left join BadgeCounts b on b.UserId = c.AnswererId
    left join Posts p2 on p2.Id = c.QuestionId
    order by c.QuestionScore desc, b.GoldBadges desc, c.AnswerScore desc
    limit 100
)
select * from Final;