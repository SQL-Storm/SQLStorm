-- {"query": "2435.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1506} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        1 as Level,
        cast(t.TagName as varchar(2000)) as Path
    from Tags t
    where t.IsRequired = 1

    union all

    select
        child.Id,
        child.TagName,
        child.Count,
        child.ExcerptPostId,
        child.WikiPostId,
        child.IsModeratorOnly,
        child.IsRequired,
        r.Level + 1,
        r.Path || ' > ' || child.TagName
    from Tags child
    join RecursiveTagHierarchy r on child.Id <> r.Id and child.TagName LIKE r.TagName || '%'
    where child.IsRequired = 1 and r.Level < 3
), LatestUserActivity as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct b.Id) as BadgeCount,
        max(b.Class) filter (where b.Class is not null) as HighestBadgeClass,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as TotalUpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as TotalDownVotes,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as UserRank
    from Users u
    left join Badges b on b.UserId = u.Id
    left join Votes v on v.UserId = u.Id and v.VoteTypeId in (2,3)
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
    having count(distinct b.Id) > 5 or u.Reputation > 1000
), PostScoreWindow as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        lag(p.Score) over (partition by p.PostTypeId order by p.CreationDate) as PrevScore,
        lead(p.Score) over (partition by p.PostTypeId order by p.CreationDate) as NextScore,
        rank() over (partition by p.PostTypeId order by p.Score desc) as ScoreRank
    from Posts p
    where p.PostTypeId in (1,2) and p.Score is not null
), AcceptedAnswers as (
    select
        q.Id as QuestionId,
        q.Title as QuestionTitle,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerId,
        au.DisplayName as AnswerOwnerName,
        q.ViewCount as QuestionViews,
        q.Tags as QuestionTags
    from Posts q
    join Posts a on a.Id = q.AcceptedAnswerId and a.PostTypeId = 2
    left join Users au on au.Id = a.OwnerUserId
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
), ComplexPostComments as (
    select
        c.PostId,
        count(*) as TotalComments,
        count(distinct c.UserId) as DistinctCommenters,
        max(c.CreationDate) as LastCommentDate,
        sum(case when length(c.Text) > 100 then 1 else 0 end) as LongComments,
        sum(case when c.UserId is null then 1 else 0 end) as AnonymousComments
    from Comments c
    group by c.PostId
), DuplicateLinkCounts as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) filter (where pl.LinkTypeId = 3) as DuplicateCount,
        count(distinct pl.RelatedPostId) filter (where pl.LinkTypeId = 1) as LinkedCount
    from PostLinks pl
    group by pl.PostId
), PostHistoryCloseInfo as (
    select
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then cast(ph.Comment as int) else null end) as CloseReasonId,
        count(case when ph.PostHistoryTypeId = 10 then 1 else null end) as TotalCloseVotes,
        count(case when ph.PostHistoryTypeId = 11 then 1 else null end) as TotalReopenVotes
    from PostHistory ph
    group by ph.PostId
)
select distinct
    lua.Id as UserId,
    lua.DisplayName as UserName,
    lua.Reputation,
    lua.BadgeCount,
    lua.HighestBadgeClass,
    lua.TotalUpVotes,
    lua.TotalDownVotes,
    psw.Id as PostId,
    psw.PostTypeId,
    psw.Title as PostTitle,
    coalesce(psw.Tags, '') as Tags,
    psw.Score,
    psw.ViewCount,
    coalesce(cpc.TotalComments, 0) as CommentCount,
    coalesce(dl.DuplicateCount, 0) as DuplicateLinks,
    coalesce(dl.LinkedCount, 0) as LinkedPosts,
    phci.CloseReasonId,
    phci.TotalCloseVotes,
    phci.TotalReopenVotes,
    aa.AnswerId,
    aa.AnswerScore,
    aa.AnswerOwnerId,
    aa.AnswerOwnerName,
    aa.QuestionViews,
    aa.QuestionTags,
    rth.Level as TagHierarchyLevel,
    rth.Path as TagHierarchyPath,
    case
        when psw.Score > 100 then 'Very High'
        when psw.Score between 50 and 100 then 'High'
        when psw.Score between 10 and 49 then 'Medium'
        else 'Low'
    end as ScoreCategory,
    case
        when lua.LastAccessDate > (now() - interval '30 days') then 'Active'
        else 'Inactive'
    end as UserActivityStatus
from LatestUserActivity lua
join PostScoreWindow psw on psw.OwnerUserId = lua.Id
left join ComplexPostComments cpc on cpc.PostId = psw.Id
left join DuplicateLinkCounts dl on dl.PostId = psw.Id
left join PostHistoryCloseInfo phci on phci.PostId = psw.Id
left join AcceptedAnswers aa on aa.QuestionId = psw.Id
left join RecursiveTagHierarchy rth on rth.TagName = any(string_to_array(coalesce(psw.Tags, ''), '><')) -- splitting tags for matching
where 
    (psw.Score > (select avg(Score) from Posts p2 where p2.PostTypeId = psw.PostTypeId) or psw.ViewCount > 1000)
    and (dl.DuplicateCount > 0 or phci.TotalCloseVotes > 0 or aa.AnswerScore is not null)
    and lua.UserRank <= 100
order by 
    lua.Reputation desc,
    psw.Score desc,
    cpc.TotalComments desc
limit 100;