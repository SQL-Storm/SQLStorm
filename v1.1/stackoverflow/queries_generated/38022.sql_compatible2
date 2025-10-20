with recent_q as (
  select p.Id as QuestionId,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         p.OwnerUserId,
         p.Tags,
         p.AcceptedAnswerId
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate >= (
      select max(CreationDate) - INTERVAL '365 days' from Posts where PostTypeId = 1
    )
),
answers as (
  select a.Id as AnswerId,
         a.ParentId as QuestionId,
         a.OwnerUserId as AnswerUserId,
         a.CreationDate as AnswerCreationDate,
         a.Score as AnswerScore
  from Posts a
  where a.PostTypeId = 2
),
first_ans as (
  select QuestionId,
         min(AnswerCreationDate) as FirstAnswerDate
  from answers
  group by QuestionId
),
tag_expanded as (
  select q.QuestionId,
         lower(trim(both ' ' from t)) as tag
  from recent_q q,
       lateral (
         select unnest(string_to_array(
           substring(coalesce(q.Tags,''), 2, greatest(length(coalesce(q.Tags,'')) - 2,0))
         , '><')) as t
       ) s
),
tag_stats as (
  select te.tag,
         count(*) as tag_q_count,
         avg(q.Score) as avg_q_score,
         avg(q.ViewCount) as avg_q_views
  from tag_expanded te
  join recent_q q on q.QuestionId = te.QuestionId
  group by te.tag
  having count(*) >= 50
),
user_activity as (
  select u.Id as UserId,
         u.Reputation,
         u.UpVotes,
         u.DownVotes,
         u.Views as ProfileViews,
         coalesce(sum(case when v.VoteTypeId = 2 then 1 when v.VoteTypeId = 3 then -1 else 0 end),0) as NetVotesCast,
         coalesce(sum(case when b.Class = 1 then 1 else 0 end),0) as GoldBadges,
         coalesce(sum(case when b.Class = 2 then 1 else 0 end),0) as SilverBadges,
         coalesce(sum(case when b.Class = 3 then 1 else 0 end),0) as BronzeBadges
  from Users u
  left join Votes v on v.UserId = u.Id and v.CreationDate >= (
    select max(CreationDate) - INTERVAL '365 days' from Votes
  )
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.Reputation, u.UpVotes, u.DownVotes, u.Views
),
q_metrics as (
  select q.QuestionId,
         q.CreationDate,
         q.Score,
         q.ViewCount,
         q.OwnerUserId,
         q.AcceptedAnswerId,
         count(a.AnswerId) as AnswerCount,
         avg(a.AnswerScore) as AvgAnswerScore,
         min(a.AnswerCreationDate) as FirstAnswerDate,
         extract(epoch from (min(a.AnswerCreationDate) - q.CreationDate))/3600.0 as HoursToFirstAnswer
  from recent_q q
  left join answers a on a.QuestionId = q.QuestionId
  group by q.QuestionId, q.CreationDate, q.Score, q.ViewCount, q.OwnerUserId, q.AcceptedAnswerId
),
q_votes as (
  select p.Id as PostId,
         sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesReceived,
         sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesReceived,
         sum(case when v.VoteTypeId = 5 then 1 else 0 end) as FavoritesReceived
  from Posts p
  join recent_q rq on rq.QuestionId = p.Id
  left join Votes v on v.PostId = p.Id
  group by p.Id
),
closures as (
  select ph.PostId,
         min(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) as FirstClosedDate,
         min(case when ph.PostHistoryTypeId = 11 then ph.CreationDate end) as FirstReopenedDate,
         sum(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as CloseEvents,
         sum(case when ph.PostHistoryTypeId = 11 then 1 else 0 end) as ReopenEvents,
         sum(case when ph.PostHistoryTypeId in (12) then 1 else 0 end) as DeleteEvents,
         sum(case when ph.PostHistoryTypeId in (13) then 1 else 0 end) as UndeleteEvents
  from PostHistory ph
  join recent_q rq on rq.QuestionId = ph.PostId
  group by ph.PostId
),
dup_links as (
  select pl.PostId as DuplicateId,
         pl.RelatedPostId as OriginalId,
         count(*) as DupLinkCount
  from PostLinks pl
  where pl.LinkTypeId = 3
  group by pl.PostId, pl.RelatedPostId
),
comment_stats as (
  select c.PostId,
         count(*) as CommentCount,
         avg(c.Score) as AvgCommentScore,
         max(c.CreationDate) as LastCommentDate
  from Comments c
  join recent_q rq on rq.QuestionId = c.PostId
  group by c.PostId
),
owner_region as (
  select u.Id as UserId,
         case
           when u.Location ilike '%united states%' or u.Location ilike '%usa%' or u.Location ilike '%u.s.%' then 'US'
           when u.Location ilike '%india%' then 'IN'
           when u.Location ilike '%united kingdom%' or u.Location ilike '%uk%' or u.Location ilike '%england%' then 'UK'
           when u.Location ilike '%germany%' then 'DE'
           when u.Location ilike '%canada%' then 'CA'
           when u.Location ilike '%australia%' then 'AU'
           when u.Location ilike '%france%' then 'FR'
           when u.Location ilike '%brazil%' then 'BR'
           when u.Location ilike '%russia%' then 'RU'
           when u.Location ilike '%china%' then 'CN'
           when u.Location ilike '%japan%' then 'JP'
           else 'OTHER'
         end as Region
  from Users u
),
q_tag_agg as (
  select te.QuestionId,
         array_agg(te.tag order by te.tag) as tags_array
  from tag_expanded te
  group by te.QuestionId
),
agg as (
  select
    qm.QuestionId,
    qm.CreationDate,
    qm.Score,
    qm.ViewCount,
    qm.AnswerCount,
    qm.AvgAnswerScore,
    qm.HoursToFirstAnswer,
    qv.UpVotesReceived,
    qv.DownVotesReceived,
    qv.FavoritesReceived,
    cs.CommentCount,
    cs.AvgCommentScore,
    cs.LastCommentDate,
    cl.FirstClosedDate,
    cl.FirstReopenedDate,
    cl.CloseEvents,
    cl.ReopenEvents,
    cl.DeleteEvents,
    cl.UndeleteEvents,
    u.Reputation as OwnerReputation,
    ua.Reputation as AnswererReputationWeighted,
    orc.Region as OwnerRegion,
    case when qm.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer,
    dt.DupLinkCount,
    ts.tag_q_count as PrimaryTagVolume,
    ts.avg_q_score as PrimaryTagAvgScore,
    ts.avg_q_views as PrimaryTagAvgViews,
    qa.tags_array
  from q_metrics qm
  left join q_votes qv on qv.PostId = qm.QuestionId
  left join comment_stats cs on cs.PostId = qm.QuestionId
  left join closures cl on cl.PostId = qm.QuestionId
  left join dup_links dt on dt.DuplicateId = qm.QuestionId
  left join Users u on u.Id = qm.OwnerUserId
  left join owner_region orc on orc.UserId = qm.OwnerUserId
  left join tag_expanded te1 on te1.QuestionId = qm.QuestionId
  left join tag_stats ts on ts.tag = te1.tag
  left join q_tag_agg qa on qa.QuestionId = qm.QuestionId
  left join (
     select a.QuestionId,
            avg(coalesce(ua.Reputation,0)) as Reputation
     from answers a
     left join Users ua on ua.Id = a.AnswerUserId
     group by a.QuestionId
  ) ua on ua.QuestionId = qm.QuestionId
)
select
  a.QuestionId,
  a.CreationDate,
  a.Score,
  a.ViewCount,
  a.AnswerCount,
  round(coalesce(a.AvgAnswerScore,0),2) as AvgAnswerScore,
  round(coalesce(a.HoursToFirstAnswer,0),2) as HoursToFirstAnswer,
  coalesce(a.UpVotesReceived,0) as UpVotesReceived,
  coalesce(a.DownVotesReceived,0) as DownVotesReceived,
  coalesce(a.FavoritesReceived,0) as FavoritesReceived,
  coalesce(a.CommentCount,0) as CommentCount,
  round(coalesce(a.AvgCommentScore,0),2) as AvgCommentScore,
  a.LastCommentDate,
  a.FirstClosedDate,
  a.FirstReopenedDate,
  coalesce(a.CloseEvents,0) as CloseEvents,
  coalesce(a.ReopenEvents,0) as ReopenEvents,
  coalesce(a.DeleteEvents,0) as DeleteEvents,
  coalesce(a.UndeleteEvents,0) as UndeleteEvents,
  coalesce(a.DupLinkCount,0) as DuplicateLinkCount,
  a.HasAcceptedAnswer,
  a.OwnerReputation,
  round(coalesce(a.AnswererReputationWeighted,0),2) as AvgAnswererReputation,
  a.OwnerRegion,
  a.PrimaryTagVolume,
  round(coalesce(a.PrimaryTagAvgScore,0),2) as PrimaryTagAvgScore,
  round(coalesce(a.PrimaryTagAvgViews,0),2) as PrimaryTagAvgViews,
  a.tags_array
from agg a
where a.ViewCount is not null
order by
  a.Score desc NULLS LAST,
  a.ViewCount desc NULLS LAST,
  a.AnswerCount desc NULLS LAST
limit 2000;