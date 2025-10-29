-- {"query": "2623.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1702}
with recursive RecursiveTags as (
    select
        Id,
        TagName,
        Count,
        ExcerptPostId,
        WikiPostId,
        IsModeratorOnly,
        IsRequired,
        1 as Level
    from Tags
    where IsRequired = true

    union all

    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        rt.Level + 1
    from Tags t
    inner join RecursiveTags rt on t.IsRequired = true and t.Id > rt.Id
    where rt.Level < 3
),
BadgedUsers as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        b.Name as BadgeName,
        b.Date as BadgeDate,
        row_number() over (partition by u.Id order by b.Class, b.Date desc) as rn
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Class is not null
),
PostScores as (
    select 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        case when p.Tags is not null then
            array_length(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><'),1)
        else 0 end as TagCount,
        coalesce((
            select count(*) 
            from Comments c 
            where c.PostId = p.Id and (c.Score > 0 or c.UserId is not null)
        ),0) as PositiveCommentCount
    from Posts p
    where p.PostTypeId in (1, 2)
),
AnswerStats as (
    select
        a.ParentId as QuestionId,
        count(*) as AnswerCount,
        sum(case when a.Score > 0 then 1 else 0 end) as PositiveAnswers,
        sum(a.Score) as TotalAnswerScore,
        max(a.Score) as MaxAnswerScore,
        avg(cast(a.Score as double precision)) as AvgAnswerScore
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
),
UserActivity as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        coalesce(pq.QuestionCount,0) as QuestionCount,
        coalesce(pa.AnswerCount,0) as AnswerCount,
        coalesce(bu.BadgeCount,0) as BadgeCount,
        coalesce(vu.UpVotes,0) as TotalUpVotes,
        coalesce(vu.DownVotes,0) as TotalDownVotes,
        coalesce(LastActivity.LastPostDate, u.CreationDate) as LastActivityDate
    from Users u
    left join (
        select OwnerUserId, count(*) as QuestionCount
        from Posts
        where PostTypeId = 1
        group by OwnerUserId
    ) pq on u.Id = pq.OwnerUserId
    left join (
        select OwnerUserId, count(*) as AnswerCount
        from Posts
        where PostTypeId = 2
        group by OwnerUserId
    ) pa on u.Id = pa.OwnerUserId
    left join (
        select UserId, count(*) as BadgeCount
        from Badges
        group by UserId
    ) bu on u.Id = bu.UserId
    left join (
        select UserId, sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes, sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Votes
        group by UserId
    ) vu on u.Id = vu.UserId
    left join (
        select OwnerUserId, max(CreationDate) as LastPostDate
        from Posts
        group by OwnerUserId
    ) LastActivity on u.Id = LastActivity.OwnerUserId
    where u.Id is not null
),
DuplicateLinks as (
    select pl.PostId, pl.RelatedPostId, pl.CreationDate, u.Id as OwnerUserId, u.DisplayName
    from PostLinks pl
    left join Posts p on pl.PostId = p.Id
    left join Users u on p.OwnerUserId = u.Id
    where pl.LinkTypeId = 3
),
RankedPosts as (
    select 
        ps.Id,
        ps.PostTypeId,
        ps.Score,
        ps.ViewCount,
        ps.TagCount,
        ps.PositiveCommentCount,
        coalesce(ans.AnswerCount,0) as AnswerCount,
        coalesce(ans.PositiveAnswers,0) as PositiveAnswers,
        coalesce(ans.TotalAnswerScore,0) as TotalAnswerScore,
        coalesce(ans.MaxAnswerScore,0) as MaxAnswerScore,
        coalesce(ans.AvgAnswerScore,0) as AvgAnswerScore,
        row_number() over (partition by ps.PostTypeId order by ps.Score desc, ps.ViewCount desc) as Rank,
        ps.OwnerUserId
    from PostScores ps
    left join AnswerStats ans on ps.Id = ans.QuestionId
),
PostWithCloseHistory as (
    select ph.PostId, ph.CreationDate, cr.Name as CloseReason
    from PostHistory ph
    left join CloseReasonTypes cr on cast(ph.Comment as integer) = cr.Id
    where ph.PostHistoryTypeId = 10
),
TitlesWithEdits as (
    select 
        p.Id,
        p.Title,
        ph.CreationDate as EditDate,
        ph.UserId as EditorUserId,
        ph.UserDisplayName as EditorName,
        ph.Comment,
        row_number() over (partition by p.Id order by ph.CreationDate desc) as rn
    from Posts p
    left join PostHistory ph on p.Id = ph.PostId and ph.PostHistoryTypeId in (1,4,7)
    where p.PostTypeId = 1
)
select distinct
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.BadgeCount,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    ua.LastActivityDate,
    rt.TagName as RequiredTag,
    rp.Id as TopScoredPostId,
    rp.Score as TopPostScore,
    rp.ViewCount as TopPostViews,
    rp.TagCount as TopPostTagCount,
    rp.PositiveCommentCount as TopPostPositiveComments,
    rp.AnswerCount as TopPostAnswerCount,
    rp.PositiveAnswers as TopPostPositiveAnswers,
    rp.TotalAnswerScore as TopPostTotalAnswerScore,
    rp.MaxAnswerScore as TopPostMaxAnswerScore,
    rp.AvgAnswerScore as TopPostAvgAnswerScore,
    phc.CloseReason as LastCloseReason,
    de.EditorName as LastEditorName,
    de.EditDate as LastEditDate,
    dl.RelatedPostId as DuplicateOfPostId,
    case 
        when u.WebsiteUrl is not null and u.WebsiteUrl like '%http%' then regexp_replace(u.WebsiteUrl, 'https?://([^/]+).*', '\1')
        else 'NoValidURL' 
    end as UserWebsiteDomain
from Users u
inner join UserActivity ua on u.Id = ua.Id
left join RecursiveTags rt on rt.Level = 1
left join RankedPosts rp on rp.OwnerUserId = u.Id and rp.Rank = 1
left join PostWithCloseHistory phc on phc.PostId = rp.Id
left join TitlesWithEdits de on de.Id = rp.Id and de.rn = 1
left join DuplicateLinks dl on dl.PostId = rp.Id
where u.Reputation >= 5000
  and (ua.QuestionCount + ua.AnswerCount) > 10
  and (rp.Score > 5 or rp.ViewCount > 1000)
  and (phc.CloseReason is null or phc.CloseReason not in ('Duplicate', 'Off-topic'))
order by u.Reputation desc, ua.QuestionCount desc;