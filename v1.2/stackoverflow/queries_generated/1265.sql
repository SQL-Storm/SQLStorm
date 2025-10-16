-- {"query": "1265.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1594} 
with RecursiveTagHierarchy as (
    select
        Id,
        TagName,
        Count,
        ExcerptPostId,
        WikiPostId,
        1 as Depth,
        cast(TagName as varchar(350)) as FullPath
    from Tags
    where IsRequired = 1
    union all
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        r.Depth + 1,
        r.FullPath || ' > ' || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.Id <> r.Id -- Self-join no parent relation in schema, rudimentary recursion for testing
    where t.Count < r.Count and r.Depth < 3
), FrequentUsersCTE as (
    select u.Id, u.DisplayName, u.Reputation,
        count(p.Id) as TotalPosts,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionsPosted,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswersPosted,
        row_number() over (order by u.Reputation desc, u.Id) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
    having count(p.Id) > 20
), UserBadgeStatsCTE as (
    select b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        max(b.Date) as MostRecentBadgeDate
    from Badges b
    where b.UserId in (select Id from FrequentUsersCTE)
    group by b.UserId
), UserActivityRanking as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.TotalPosts,
        u.QuestionsPosted,
        u.AnswersPosted,
        coalesce(b.GoldBadges,0) as GoldBadges,
        coalesce(b.SilverBadges,0) as SilverBadges,
        coalesce(b.BronzeBadges,0) as BronzeBadges,
        us.PrintRank,
        rank() over (order by u.TotalPosts desc, GoldBadges desc, u.Reputation desc) as ActivityRank
    from FrequentUsersCTE u
    left join UserBadgeStatsCTE b on b.UserId = u.Id
    join (select Id, UserRank as PrintRank from FrequentUsersCTE) us on us.Id = u.Id
), CloseDuplicateQuestions as (
    select ph.PostId, ph.CreationDate as CloseDate, crt.Name as CloseReason,
        p.Id as QuestionId, p.Title, p.Score, p.ViewCount
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int) and ph.PostHistoryTypeId = 10
    join Posts p on p.Id = ph.PostId and p.PostTypeId = 1
    where crt.Name like '%Duplicate%'
), AnswerQualityStats as (
    select
        a.OwnerUserId,
        count(*) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        sum(case when a.Id = pq.AcceptedAnswerId then 1 else 0 end) as AcceptedCount,
        count(distinct pq.Id) as RelatedQuestionsAnswered
    from Posts a
    left join Posts pq on pq.AcceptedAnswerId = a.Id and pq.PostTypeId = 1
    where a.PostTypeId = 2 and a.OwnerUserId is not null
    group by a.OwnerUserId
), PostLinkSummary as (
    select
        pl.PostId,
        count(*) filter (where pl.LinkTypeId = 1) as LinkedPostsCount,
        count(*) filter (where pl.LinkTypeId = 3) as DuplicatePostsCount,
        max(pl.CreationDate) as LatestLinkDate
    from PostLinks pl
    group by pl.PostId
), ComplexPostsSelection AS (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Score,
        c.LinkedPostsCount,
        c.DuplicatePostsCount,
        a.AnswerCount,
        a.AvgAnswerScore,
        u.DisplayName as OwnerName,
        lag(p.Score) over (partition by p.PostTypeId order by p.CreationDate) as PrevScore,
        lead(p.Score) over (partition by p.PostTypeId order by p.CreationDate) as NextScore,
        case
            when p.ClosedDate is not null then 'Closed'
            when p.AcceptedAnswerId is not null then 'AcceptedAnswer'
            when p.FavoriteCount > 10 then 'Popular'
            else 'Open'
        end as PostStatus,
        coalesce(cd.CloseReason, 'N/A') as CloseReason,
        row_number() over (partition by p.PostTypeId order by p.Score desc) as PostRankWithinType
    from Posts p
    left join PostLinkSummary c on c.PostId = p.Id
    left join AnswerQualityStats a on a.OwnerUserId = p.OwnerUserId
    left join Users u on u.Id = p.OwnerUserId
    left join CloseDuplicateQuestions cd on cd.QuestionId = p.Id
    where p.CreationDate > '2009-01-01' and p.Score is not null
)
select 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.TotalPosts,
    u.QuestionsPosted,
    u.AnswersPosted,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    eq.Id as ExamplePostId,
    eq.Title as ExamplePostTitle,
    eq.PostTypeId,
    eq.Score as PostScore,
    eq.PostStatus,
    eq.CloseReason,
    eq.LinkedPostsCount,
    eq.DuplicatePostsCount,
    eq.AnswerCount,
    round(eq.AvgAnswerScore::numeric,2) as AverageAnswerScore,
    string_agg(distinct r.FullPath, ' | ') as TagHierarchies
from UserActivityRanking u
left join Lateral (
    select cps.Id, cps.Title, cps.PostTypeId, cps.Score, cps.PostStatus, cps.CloseReason,
           cps.LinkedPostsCount, cps.DuplicatePostsCount, cps.AnswerCount, cps.AvgAnswerScore
    from ComplexPostsSelection cps
    where cps.OwnerName = u.DisplayName
    order by cps.Score desc nulls last
    limit 1
) eq on true
left join Posts pt on pt.OwnerUserId = u.Id and pt.PostTypeId = 1
left join RecursiveTagHierarchy r on r.ExcerptPostId = pt.Id or r.WikiPostId = pt.Id
group by u.Id, u.DisplayName, u.Reputation, u.TotalPosts, u.QuestionsPosted, u.AnswersPosted, 
         u.GoldBadges, u.SilverBadges, u.BronzeBadges, eq.Id, eq.Title, eq.PostTypeId, 
         eq.Score, eq.PostStatus, eq.CloseReason, eq.LinkedPostsCount, eq.DuplicatePostsCount, 
         eq.AnswerCount, eq.AvgAnswerScore
having u.TotalPosts > 50
order by u.Reputation desc, u.GoldBadges desc, u.TotalPosts desc
limit 50;