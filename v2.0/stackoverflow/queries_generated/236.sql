-- {"query": "236.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2899} 
with recent_activity as (
  select
    p.Id as PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Title,
    p.Tags,
    coalesce(p.AnswerCount, 0) as AnswerCount,
    p.ClosedDate,
    p.CommunityOwnedDate,
    p.LastActivityDate,
    u.Reputation,
    u.DisplayName,
    u.Location,
    rank() over (partition by p.OwnerUserId order by p.LastActivityDate desc nulls last, p.Id desc) as rnk_last_activity
  from Posts p
  left join Users u on u.Id = p.OwnerUserId
  where p.CreationDate >= (select date_trunc('month', max(CreationDate)) - interval '12 months' from Posts)
),
comment_rollup as (
  select
    c.PostId,
    count(*) as CommentCount,
    sum(coalesce(c.Score, 0)) as CommentScoreSum,
    max(c.CreationDate) as LastCommentDate,
    count(*) filter (where c.Score > 0) as PositiveComments,
    count(*) filter (where c.Score < 0) as NegativeComments
  from Comments c
  group by c.PostId
),
vote_rollup as (
  select
    v.PostId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
    sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountyTotal,
    max(v.CreationDate) as LastVoteDate
  from Votes v
  group by v.PostId
),
postlinks_rollup as (
  select
    pl.PostId,
    sum(case when pl.LinkTypeId = 1 then 1 else 0 end) as LinkedCount,
    sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as DuplicateCount,
    max(pl.CreationDate) as LastLinkDate
  from PostLinks pl
  group by pl.PostId
),
edits_rollup as (
  select
    ph.PostId,
    count(*) filter (where ph.PostHistoryTypeId in (4,5,6)) as EditCount,
    count(*) filter (where ph.PostHistoryTypeId = 10) as ClosedEvents,
    count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenEvents,
    max(ph.CreationDate) as LastEditEventDate,
    max(case when ph.PostHistoryTypeId in (10,11,12,13,14,15,19,20,35) then ph.CreationDate end) as LastModEventDate,
    max(case when ph.PostHistoryTypeId = 10 then ph.Comment end) as LastCloseReasonId
  from PostHistory ph
  group by ph.PostId
),
user_badge_stats as (
  select
    b.UserId,
    count(*) as TotalBadges,
    count(*) filter (where b.Class = 1) as GoldBadges,
    count(*) filter (where b.Class = 2) as SilverBadges,
    count(*) filter (where b.Class = 3) as BronzeBadges,
    count(*) filter (where b.TagBased = 1) as TagBadges,
    max(b.Date) as LastBadgeDate
  from Badges b
  group by b.UserId
),
question_tag_expansion as (
  select
    p.Id as PostId,
    unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as TagName
  from Posts p
  where p.PostTypeId = 1
    and p.Tags is not null
    and length(p.Tags) > 2
),
tag_stats as (
  select
    qte.PostId,
    count(*) as TagCount,
    sum(t.Count) as SumTagGlobalCount,
    min(t.Count) as MinTagGlobalCount,
    max(t.Count) as MaxTagGlobalCount,
    bool_or(coalesce(t.IsModeratorOnly, 0) = 1) as HasModOnlyTag,
    bool_or(coalesce(t.IsRequired, 0) = 1) as HasRequiredTag
  from question_tag_expansion qte
  left join Tags t on lower(t.TagName) = lower(qte.TagName)
  group by qte.PostId
),
accepted_answer_age as (
  select
    q.Id as QuestionId,
    a.Id as AcceptedAnswerId,
    extract(epoch from (a.CreationDate - q.CreationDate))::bigint as AcceptedAfterSeconds
  from Posts q
  join Posts a on a.Id = q.AcceptedAnswerId
  where q.PostTypeId = 1
),
owner_activity as (
  select
    u.Id as UserId,
    count(*) as OwnerPostCount,
    sum(case when p.PostTypeId = 1 then 1 else 0 end) as OwnerQuestionCount,
    sum(case when p.PostTypeId = 2 then 1 else 0 end) as OwnerAnswerCount,
    max(p.LastActivityDate) as OwnerLastActivity
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  group by u.Id
),
quality_scoring as (
  select
    ra.PostId,
    ra.PostTypeId,
    ra.OwnerUserId,
    coalesce(vr.UpVotes,0) - coalesce(vr.DownVotes,0) as NetVotes,
    coalesce(vr.Favorites,0) as Favorites,
    coalesce(vr.BountyTotal,0) as BountyTotal,
    coalesce(cr.CommentScoreSum,0) as CommentScoreSum,
    coalesce(cr.CommentCount,0) as CommentCount,
    coalesce(er.EditCount,0) as EditCount,
    coalesce(plr.LinkedCount,0) as LinkedCount,
    coalesce(plr.DuplicateCount,0) as DuplicateCount,
    coalesce(ts.TagCount, case when ra.PostTypeId = 1 then 0 else null end) as TagCount,
    coalesce(ts.SumTagGlobalCount,0) as SumTagGlobalCount,
    case
      when ra.ViewCount is null or ra.ViewCount = 0 then null
      else round((ra.Score::numeric / nullif(ra.ViewCount,0)) * 1000, 4)
    end as ScorePerThousandViews,
    round(
      (
        coalesce(vr.UpVotes,0)*2
        - coalesce(vr.DownVotes,0)*1.5
        + coalesce(vr.Favorites,0)*1.2
        + coalesce(vr.BountyTotal,0)/100.0
        + greatest(least(coalesce(cr.CommentScoreSum,0), 10), -5)
        + least(coalesce(er.EditCount,0), 10)*0.5
        + coalesce(plr.LinkedCount,0)*0.3
        - coalesce(plr.DuplicateCount,0)*2
        + case when ra.PostTypeId = 1 then least(coalesce(ts.TagCount,0),5)*0.2 else 0 end
        + case when ra.ClosedDate is not null then -3 else 0 end
        + case when ra.CommunityOwnedDate is not null then 1 else 0 end
      )
      , 3
    ) as QualityScore
  from recent_activity ra
  left join vote_rollup vr on vr.PostId = ra.PostId
  left join comment_rollup cr on cr.PostId = ra.PostId
  left join edits_rollup er on er.PostId = ra.PostId
  left join postlinks_rollup plr on plr.PostId = ra.PostId
  left join tag_stats ts on ts.PostId = ra.PostId
),
top_owner_posts as (
  select
    qs.OwnerUserId,
    qs.PostId,
    qs.QualityScore,
    row_number() over (partition by qs.OwnerUserId order by qs.QualityScore desc nulls last, qs.PostId desc) as rn_quality
  from quality_scoring qs
),
dedup_dupes as (
  select distinct on (least(pl.PostId, pl.RelatedPostId), greatest(pl.PostId, pl.RelatedPostId))
    least(pl.PostId, pl.RelatedPostId) as A,
    greatest(pl.PostId, pl.RelatedPostId) as B,
    pl.CreationDate
  from PostLinks pl
  where pl.LinkTypeId = 3
  order by least(pl.PostId, pl.RelatedPostId), greatest(pl.PostId, pl.RelatedPostId), pl.CreationDate desc
),
owner_recent_rank as (
  select
    ra.OwnerUserId,
    ra.PostId,
    ra.rnk_last_activity,
    dense_rank() over (partition by ra.OwnerUserId order by ra.CreationDate desc nulls last) as rnk_creation
  from recent_activity ra
),
suspicious_nulls as (
  select
    p.Id as PostId,
    (p.OwnerUserId is null and p.OwnerDisplayName is not null) as HasOrphanOwnerDisplay,
    (p.OwnerUserId is not null and p.OwnerDisplayName is null) as HasMissingOwnerDisplay,
    (p.LastEditorUserId is null and p.LastEditorDisplayName is not null) as HasOrphanEditorDisplay,
    (p.LastEditorUserId is not null and p.LastEditorDisplayName is null) as HasMissingEditorDisplay
  from Posts p
)
select
  qs.PostId,
  pt.Name as PostType,
  coalesce(qs.QualityScore, 0) as QualityScore,
  qs.ScorePerThousandViews,
  qs.NetVotes,
  qs.Favorites,
  qs.BountyTotal,
  qs.CommentCount,
  qs.EditCount,
  qs.LinkedCount,
  qs.DuplicateCount,
  ts.TagCount,
  ts.SumTagGlobalCount,
  case when aa.AcceptedAfterSeconds is not null
       then to_char(make_interval(secs => aa.AcceptedAfterSeconds), 'HH24:MI:SS')
       else null end as AcceptedAfter,
  ra.Title,
  case when ra.Tags is not null then substring(ra.Tags, 1, 120) || case when length(ra.Tags) > 120 then '…' else '' end end as TagsPreview,
  ra.ViewCount,
  ra.AnswerCount,
  ra.ClosedDate,
  ra.LastActivityDate,
  u.Id as OwnerUserId,
  coalesce(u.DisplayName, '[user ' || u.Id || ']') as OwnerDisplayName,
  u.Reputation,
  obs.TotalBadges,
  obs.GoldBadges,
  obs.SilverBadges,
  obs.BronzeBadges,
  obs.TagBadges,
  orr.rnk_last_activity as OwnerActivityRank,
  orr.rnk_creation as OwnerCreationRank,
  topq.rn_quality as OwnerQualityRank,
  sn.HasOrphanOwnerDisplay,
  sn.HasMissingOwnerDisplay,
  sn.HasOrphanEditorDisplay,
  sn.HasMissingEditorDisplay,
  er.LastEditEventDate,
  er.LastModEventDate,
  vr.LastVoteDate,
  plr.LastLinkDate,
  greatest(coalesce(er.LastEditEventDate,'epoch'::timestamp),
           coalesce(vr.LastVoteDate,'epoch'::timestamp),
           coalesce(plr.LastLinkDate,'epoch'::timestamp),
           coalesce(ra.LastActivityDate,'epoch'::timestamp)) as LastSignalDate
from quality_scoring qs
join recent_activity ra on ra.PostId = qs.PostId
left join PostTypes pt on pt.Id = ra.PostTypeId
left join Users u on u.Id = ra.OwnerUserId
left join user_badge_stats obs on obs.UserId = ra.OwnerUserId
left join owner_recent_rank orr on orr.PostId = ra.PostId and orr.OwnerUserId = ra.OwnerUserId
left join top_owner_posts topq on topq.PostId = ra.PostId and topq.OwnerUserId = ra.OwnerUserId
left join edits_rollup er on er.PostId = ra.PostId
left join vote_rollup vr on vr.PostId = ra.PostId
left join postlinks_rollup plr on plr.PostId = ra.PostId
left join tag_stats ts on ts.PostId = ra.PostId
left join accepted_answer_age aa on aa.QuestionId = ra.PostId
left join suspicious_nulls sn on sn.PostId = ra.PostId
where (
    qs.QualityScore > (
      select percentile_cont(0.75) within group (order by qs2.QualityScore)
      from quality_scoring qs2
    )
    or (
      ra.PostTypeId = 1
      and exists (
        select 1
        from dedup_dupes d
        where d.A = ra.Id or d.B = ra.Id
      )
    )
  )
and coalesce(ts.HasModOnlyTag,false) = false
and (u.Reputation is null or u.Reputation >= 100)
order by
  qs.QualityScore desc nulls last,
  qs.NetVotes desc nulls last,
  ra.ViewCount desc nulls last,
  qs.PostId desc
limit 500;