-- {"query": "2475.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1151} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.IsModeratorOnly,
        t.IsRequired,
        1 as Level,
        cast(t.TagName as varchar(255)) as Path
    from Tags t
    where t.IsRequired = 1
    union all
    select
        child.Id,
        child.TagName,
        child.Count,
        child.IsModeratorOnly,
        child.IsRequired,
        r.Level + 1,
        r.Path || '->' || child.TagName
    from Tags child
    join RecursiveTagHierarchy r on char_length(r.Path) < 100
    where child.IsRequired = 0
      and child.Id <> r.Id
)
, PostScores AS (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        row_number() over (partition by p.PostTypeId order by p.Score desc) as ScoreRank,
        avg(coalesce(p.Score,0)) over (partition by p.PostTypeId) as AvgScore,
        sum(coalesce(p.ViewCount,0)) over (partition by p.PostTypeId) as TotalViews,
        count(*) over (partition by p.PostTypeId) as PostsCount
    from Posts p
    where p.CreationDate >= current_date - interval '365 days'
)
, UserBadgeSummary AS (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct case when b.Class = 1 then b.Id end) as GoldBadges,
        count(distinct case when b.Class = 2 then b.Id end) as SilverBadges,
        count(distinct case when b.Class = 3 then b.Id end) as BronzeBadges,
        max(b.Date) as LastBadgeDate,
        bool_or(b.TagBased = 1) as HasTagBasedBadge
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName
)
, AcceptedAnswers AS (
    select
        q.Id as QuestionId,
        a.Id as AcceptedAnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        a.OwnerUserId as AnswerOwnerUserId,
        EXISTS (
            select 1 from Votes v where v.PostId = a.Id and v.VoteTypeId = 2 limit 1
        ) as HasUpvotes
    from Posts q
    left join Posts a on q.AcceptedAnswerId = a.Id
    where q.PostTypeId = 1
)
select distinct
    p.PostId,
    p.Title,
    p.PostTypeId,
    case 
        when p.ViewCount > p.TotalViews / p.PostsCount * 2 then 'Highly Viewed'
        when p.ViewCount is null then 'Unknown Views'
        else 'Normal Views'
    end as ViewCategory,
    p.Score,
    p.AvgScore,
    u.DisplayName as OwnerUserName,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    u.HasTagBasedBadge,
    aa.AcceptedAnswerId,
    aa.AnswerScore,
    aa.HasUpvotes,
    string_agg(distinct ph.Name, ', ') as PostHistoryEvents,
    string_agg(distinct lt.Name, ', ') as LinkedPostTypes,
    count(distinct c.Id) filter (where c.Score > 2) as HighScoreComments,
    max(phHist.CreationDate) as LastPostHistoryDate,
    rh.Level as TagHierarchyLevel,
    rh.Path as TagHierarchyPath,
    sum(case when lower(p.Tags) like '%' || lower(rh.TagName) || '%' then 1 else 0 end) over (partition by p.PostId) as TagsMatchCount
from PostScores p
left join Users u on u.Id = p.OwnerUserId
left join AcceptedAnswers aa on aa.QuestionId = p.PostId
left join PostHistory phHist on phHist.PostId = p.PostId and phHist.PostHistoryTypeId in (10,11,19,20)
left join PostHistoryTypes ph on ph.Id = phHist.PostHistoryTypeId
left join PostLinks pl on pl.PostId = p.PostId
left join LinkTypes lt on lt.Id = pl.LinkTypeId
left join Comments c on c.PostId = p.PostId
left join RecursiveTagHierarchy rh on (
    p.Tags is not null
    and rh.TagName is not null
    and position('<' || rh.TagName || '>' in p.Tags) > 0
)
where p.ScoreRank <= 100
group by
    p.PostId,
    p.Title,
    p.PostTypeId,
    p.ViewCount,
    p.Score,
    p.AvgScore,
    p.TotalViews,
    p.PostsCount,
    u.DisplayName,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    u.HasTagBasedBadge,
    aa.AcceptedAnswerId,
    aa.AnswerScore,
    aa.HasUpvotes,
    rh.Level,
    rh.Path
having count(distinct c.Id) filter (where c.Score > 2) > 0
order by p.Score desc, p.ViewCount desc, p.CreationDate desc
limit 50;