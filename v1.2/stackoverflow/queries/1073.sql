with RecursiveTagStats as (
    select
        t.Id,
        t.TagName,
        t.Count,
        p.ViewCount,
        p.Score,
        p.CreationDate,
        row_number() over (partition by t.Id order by p.Score desc, p.ViewCount desc) as rn
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    where t.IsModeratorOnly = false and t.IsRequired = false
),
TopTags as (
    select Id, TagName, Count from RecursiveTagStats where rn = 1
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationRank as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        rank() over (order by u.Reputation desc) as RepRank,
        count(distinct p.Id) as PostCount
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.CreationDate >= cast('2023-01-01' as timestamp) and p.PostTypeId in (1,2)
    group by u.Id, u.DisplayName, u.Reputation
),
PostLinkDupes as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Duplicate') as DuplicateCount,
        max(pl.CreationDate) as LastDuplicateLinkDate
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId
),
LatestPostHistoryClose as (
    select distinct on (ph.PostId)
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason,
        ph.UserId as CloserUserId
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    where pht.Name = 'Post Closed'
    order by ph.PostId, ph.CreationDate desc
),
AnswerStats as (
    select
        p.ParentId as QuestionId,
        count(p.Id) as TotalAnswers,
        sum(case when p.Score > 0 then 1 else 0 end) as PositiveAnswers,
        avg(p.Score) filter (where p.Score is not null) as AvgAnswerScore
    from Posts p
    where p.PostTypeId = 2
    group by p.ParentId
),
QuestionStats as (
    select
        q.Id,
        q.Title,
        q.Tags,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.CommentCount,
        COALESCE(pld.DuplicateCount,0) as DuplicateCount,
        pstat.TotalAnswers,
        pstat.PositiveAnswers,
        pstat.AvgAnswerScore,
        lph.CloseDate,
        lph.CloseReason,
        q.OwnerUserId,
        u.DisplayName as OwnerName,
        coalesce(ubc_badge.BadgeCount,0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount,0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount,0) as BronzeBadges
    from Posts q
    left join PostLinkDupes pld on q.Id = pld.PostId
    left join AnswerStats pstat on q.Id = pstat.QuestionId
    left join LatestPostHistoryClose lph on q.Id = lph.PostId
    left join Users u on q.OwnerUserId = u.Id
    left join (
        select UserId, BadgeCount from UserBadgeCounts where Class = 1
    ) ubc_badge on q.OwnerUserId = ubc_badge.UserId
    left join (
        select UserId, BadgeCount from UserBadgeCounts where Class = 2
    ) ubc_silver on q.OwnerUserId = ubc_silver.UserId
    left join (
        select UserId, BadgeCount from UserBadgeCounts where Class = 3
    ) ubc_bronze on q.OwnerUserId = ubc_bronze.UserId
    where q.PostTypeId = 1
),
QuestionRankings as (
  select
      qs.Id,
      qs.Title,
      qs.Tags,
      qs.CreationDate,
      qs.Score,
      qs.ViewCount,
      qs.AnswerCount,
      qs.CommentCount,
      qs.DuplicateCount,
      qs.TotalAnswers,
      qs.PositiveAnswers,
      qs.AvgAnswerScore,
      qs.CloseDate,
      qs.CloseReason,
      qs.OwnerUserId,
      qs.OwnerName,
      qs.GoldBadges,
      qs.SilverBadges,
      qs.BronzeBadges,
      row_number() over (
          partition by 
              case when qs.CloseDate is null then 'open' else 'closed' end
          order by 
              qs.Score desc, 
              qs.ViewCount desc,
              qs.AnswerCount desc,
              qs.DuplicateCount asc
      ) as RankInStatus
  from QuestionStats qs
)
select
    qr.Id as QuestionId,
    qr.Title,
    qr.OwnerName,
    qr.Score,
    qr.ViewCount,
    qr.AnswerCount,
    qr.CommentCount,
    qr.DuplicateCount,
    qr.TotalAnswers,
    qr.PositiveAnswers,
    round(cast(qr.AvgAnswerScore as numeric),2) as AvgAnswerScore,
    qr.CloseDate,
    qr.CloseReason,
    qr.GoldBadges,
    qr.SilverBadges,
    qr.BronzeBadges,
    case 
        when qr.CloseDate is null then 'Open' 
        else 'Closed' 
    end as QuestionStatus,
    qr.RankInStatus,
    case 
      when qr.Tags is not null then
        (
          select string_agg(tt.TagName || '(' || cast(tt.Count as text) || ')', ', ' order by tt.Count desc)
          from TopTags tt
          where position('<' || tt.TagName || '>' in qr.Tags) > 0
        )
      else 'No Tags'
    end as TopRelevantTags,
    coalesce(
        date_part('day', cast('2024-10-01 12:34:56' as timestamp) - qr.CreationDate),
        -1
    ) as DaysSinceCreation,
    urr.RepRank as OwnerReputationRank,
    urr.Reputation as OwnerReputation,
    (select count(*) from Badges b where b.UserId = qr.OwnerUserId and b.Date > qr.CreationDate - interval '30 days') as RecentBadgesCount
from QuestionRankings qr
left join UserReputationRank urr on qr.OwnerUserId = urr.Id
where qr.RankInStatus <= 100
order by QuestionStatus, qr.RankInStatus;