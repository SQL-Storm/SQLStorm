-- {"query": "484.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1478} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 as Level,
        cast(t.TagName as varchar(1000)) as Path
    from Tags t
    where t.IsRequired = 1

    union all

    select
        c.Id,
        c.TagName,
        c.Count,
        c.ExcerptPostId,
        c.WikiPostId,
        r.Level + 1,
        r.Path || ' > ' || c.TagName
    from Tags c
    inner join RecursiveTagHierarchy r on c.Id = (
        select pl.RelatedPostId from PostLinks pl
        join Posts p on p.Id = pl.PostId
        where p.Tags like '%' || r.TagName || '%'
        and pl.LinkTypeId = 1
        limit 1
    )
    where r.Level < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserActivityStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        coalesce(sum(vt2.UpVotes),0) as TotalUpVotes,
        coalesce(sum(vt2.DownVotes),0) as TotalDownVotes,
        max(p.CreationDate) as LastPostDate,
        min(p.CreationDate) as FirstPostDate,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as LastCloseDate,
        count(distinct c.Id) as CommentsMade
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select
            p.OwnerUserId,
            sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Posts p
        left join Votes v on v.PostId = p.Id
        group by p.OwnerUserId
    ) vt2 on vt2.OwnerUserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, vt2.UpVotes, vt2.DownVotes
),
TopPostsWithWindow as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as rn,
        count(*) over (partition by p.OwnerUserId) as TotalPostsByUser,
        avg(p.Score) over (partition by p.OwnerUserId) as AvgScoreByUser,
        max(p.Score) over (partition by p.OwnerUserId) as MaxScoreByUser,
        case when p.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
),
ComplexUserSummary as (
    select
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        coalesce(ubc_gold.BadgeCount,0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount,0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount,0) as BronzeBadges,
        uas.QuestionsAsked,
        uas.AnswersGiven,
        uas.TotalUpVotes,
        uas.TotalDownVotes,
        uas.CommentsMade,
        uas.FirstPostDate,
        uas.LastPostDate,
        uas.LastCloseDate,
        max(tph.Level) as MaxTagHierarchyLevel,
        string_agg(distinct tph.Path, ' | ') as TagPaths
    from UserActivityStats uas
    left join UserBadgeCounts ubc_gold on ubc_gold.UserId = uas.UserId and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on ubc_silver.UserId = uas.UserId and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on ubc_bronze.UserId = uas.UserId and ubc_bronze.Class = 3
    left join RecursiveTagHierarchy tph on tph.TagName = any(string_to_array(coalesce((select p.Tags from Posts p where p.OwnerUserId = uas.UserId limit 1),''), '><'))
    group by
        uas.UserId, uas.DisplayName, uas.Reputation,
        ubc_gold.BadgeCount, ubc_silver.BadgeCount, ubc_bronze.BadgeCount,
        uas.QuestionsAsked, uas.AnswersGiven, uas.TotalUpVotes, uas.TotalDownVotes,
        uas.CommentsMade, uas.FirstPostDate, uas.LastPostDate, uas.LastCloseDate
)
select
    cus.UserId,
    cus.DisplayName,
    cus.Reputation,
    cus.GoldBadges,
    cus.SilverBadges,
    cus.BronzeBadges,
    cus.QuestionsAsked,
    cus.AnswersGiven,
    cus.TotalUpVotes,
    cus.TotalDownVotes,
    cus.CommentsMade,
    cus.FirstPostDate,
    cus.LastPostDate,
    cus.LastCloseDate,
    cus.MaxTagHierarchyLevel,
    cus.TagPaths,
    coalesce(tp.Title, 'No Top Question') as TopQuestionTitle,
    coalesce(tp.Score, 0) as TopQuestionScore,
    coalesce(tp.ViewCount, 0) as TopQuestionViews,
    tp.HasAcceptedAnswer,
    case
        when cus.LastCloseDate is not null and cus.LastCloseDate > now() - interval '30 days' then 'Recently Closed Post'
        when cus.QuestionsAsked = 0 and cus.AnswersGiven > 10 then 'Answerer'
        when cus.QuestionsAsked > 10 and cus.AnswersGiven = 0 then 'Questioner'
        when cus.QuestionsAsked > 10 and cus.AnswersGiven > 10 then 'Active Contributor'
        else 'Casual User'
    end as UserCategory
from ComplexUserSummary cus
left join TopPostsWithWindow tp on tp.OwnerUserId = cus.UserId and tp.rn = 1
where cus.Reputation > 1000
order by cus.Reputation desc, cus.GoldBadges desc, cus.SilverBadges desc
limit 100;