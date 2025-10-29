-- {"query": "2414.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1619} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        array[t.Id] as AncestorPath
    from Tags t
    where t.IsModeratorOnly = 0

    union all

    select
        c.Id,
        c.TagName,
        c.Count,
        r.AncestorPath || c.Id
    from Tags c
    join RecursiveTagHierarchy r on c.Id <> all(r.AncestorPath)
    where c.IsModeratorOnly = 0
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
        count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
        count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostScoreWindows as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        dense_rank() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc nulls last) as ScoreRank,
        lag(p.Score) over (partition by p.PostTypeId order by p.Score desc) as PrevScore,
        lead(p.Score) over (partition by p.PostTypeId order by p.Score desc) as NextScore
    from Posts p
    where p.PostTypeId in (1, 2)
      and p.CreationDate >= current_date - interval '1 year'
),
TopQuestionsWithAcceptedAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.Score as QuestionScore,
        q.ViewCount,
        a.Id as AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        u.DisplayName as QuestionOwnerName,
        ua.DisplayName as AnswerOwnerName
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    left join Users u on u.Id = q.OwnerUserId
    left join Users ua on ua.Id = a.OwnerUserId
    where q.PostTypeId = 1
      and q.Score > (
          select avg(Score) 
          from Posts 
          where PostTypeId = 1
          and CreationDate >= current_date - interval '1 year'
        )
),
CommentsSummary as (
    select
        c.PostId,
        count(*) as TotalComments,
        count(distinct c.UserId) as UniqueCommenters,
        max(c.CreationDate) as LastCommentDate,
        min(c.CreationDate) as FirstCommentDate
    from Comments c
    group by c.PostId
),
QuestionCloseReasonCounts as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        count(*) as CloseCount
    from PostHistory ph
    join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id and ph.PostHistoryTypeId = 10
    group by ph.PostId, crt.Name
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        ltk.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes ltk on ltk.Id = pl.LinkTypeId
    where ltk.Name = 'Duplicate'
),
QuestionsWithDuplicates as (
    select
        q.Id,
        q.Title,
        count(dl.RelatedPostId) as DuplicateCount
    from Posts q
    left join DuplicateLinks dl on dl.PostId = q.Id
    where q.PostTypeId = 1
    group by q.Id, q.Title
),
UserReputationTrend as (
    select
        u.Id as UserId,
        u.DisplayName,
        date_trunc('month', ph.CreationDate) as Month,
        sum(case when ph.PostHistoryTypeId in (24, 25) then 10 else 0 end) as EditPoints,
        count(distinct b.Id) as BadgeCount,
        row_number() over (partition by u.Id order by date_trunc('month', ph.CreationDate)) as MonthRank
    from Users u
    left join PostHistory ph on ph.UserId = u.Id and ph.CreationDate > current_date - interval '1 year'
    left join Badges b on b.UserId = u.Id and b.Date > current_date - interval '1 year'
    group by u.Id, u.DisplayName, date_trunc('month', ph.CreationDate)
),
FinalStats AS (
    select
        tq.QuestionId,
        tq.Title,
        tq.QuestionScore,
        tq.ViewCount,
        tq.AcceptedAnswerId,
        tq.AcceptedAnswerScore,
        tq.QuestionOwnerName,
        coalesce(ub.GoldBadges,0) as GoldBadges,
        coalesce(ub.SilverBadges,0) as SilverBadges,
        coalesce(ub.BronzeBadges,0) as BronzeBadges,
        coalesce(cs.TotalComments,0) as TotalComments,
        coalesce(cs.UniqueCommenters,0) as UniqueCommenters,
        coalesce(qdc.DuplicateCount,0) as DuplicateCount,
        crc.CloseReason,
        crc.CloseCount,
        case
            when tq.QuestionScore > 100 and tq.ViewCount > 10000 then 'High Traffic'
            when tq.QuestionScore between 50 and 100 then 'Medium Traffic'
            else 'Low Traffic'
        end as TrafficCategory,
        case
            when ub.GoldBadges > 5 then 'Top Badge Earner'
            when ub.SilverBadges > 10 then 'Medium Badge Earner'
            else 'New User or Few Badges'
        end as UserBadgeCategory,
        concat(
            'Score: ', tq.QuestionScore::text, ', Views: ', coalesce(tq.ViewCount, 0)::text,
            ', Comments: ', coalesce(cs.TotalComments,0)::text
        ) as SummaryStats,
        urep.Month,
        urep.EditPoints,
        urep.BadgeCount
    from TopQuestionsWithAcceptedAnswers tq
    left join UserBadgeStats ub on ub.UserId = tq.OwnerUserId
    left join CommentsSummary cs on cs.PostId = tq.QuestionId
    left join QuestionsWithDuplicates qdc on qdc.Id = tq.QuestionId
    left join QuestionCloseReasonCounts crc on crc.PostId = tq.QuestionId
    left join UserReputationTrend urep on urep.UserId = tq.OwnerUserId
    where (crc.CloseCount is null or crc.CloseCount < 5)
)
select distinct
    fs.QuestionId,
    fs.Title,
    fs.TrafficCategory,
    fs.UserBadgeCategory,
    fs.SummaryStats,
    fs.DuplicateCount,
    fs.CloseReason,
    fs.CloseCount,
    fs.Month,
    fs.EditPoints,
    fs.BadgeCount
from FinalStats fs
where (fs.DuplicateCount > 0 or fs.CloseCount > 0 or fs.GoldBadges > 3)
  and fs.Month = (
    select max(Month) from UserReputationTrend ur where ur.UserId = fs.QuestionOwnerName::int
  )
order by fs.TrafficCategory desc nulls last, fs.DuplicateCount desc, fs.CloseCount desc
limit 100;