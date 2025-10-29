-- {"query": "789.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3151} 
with
q as (
  select p.Id as QuestionId,
         p.OwnerUserId,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         p.Tags,
         p.Title,
         p.AcceptedAnswerId,
         coalesce(p.AnswerCount, 0) as AnswerCount
  from Posts p
  where p.PostTypeId = 1
),
a as (
  select a.ParentId as QuestionId,
         a.Id as AnswerId,
         a.OwnerUserId as AnswerOwnerId,
         a.Score as AnswerScore,
         a.CreationDate as AnswerCreationDate
  from Posts a
  where a.PostTypeId = 2
),
u as (
  select u.Id as UserId,
         u.DisplayName,
         u.Reputation,
         u.CreationDate as UserCreationDate,
         u.Location,
         u.UpVotes,
         u.DownVotes,
         nullif(trim(coalesce(u.WebsiteUrl, '')),'') as WebsiteUrl
  from Users u
),
q_votes as (
  select v.PostId,
         sum(case when v.VoteTypeId = 2 then 1 when v.VoteTypeId = 3 then -1 else 0 end) as NetVotes,
         sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpvoteCount,
         sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownvoteCount,
         sum(case when v.VoteTypeId = 5 then 1 else 0 end) as FavoriteCount
  from Votes v
  group by v.PostId
),
c as (
  select c.PostId,
         count(*) as CommentCount,
         max(c.CreationDate) as LastCommentDate,
         sum(greatest(0, coalesce(c.Score,0))) as CommentKudos
  from Comments c
  group by c.PostId
),
q_links as (
  select pl.PostId,
         sum(case when pl.LinkTypeId = 1 then 1 else 0 end) as LinkedCount,
         sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as DuplicateCount
  from PostLinks pl
  group by pl.PostId
),
q_edits as (
  select ph.PostId,
         count(*) filter (where ph.PostHistoryTypeId in (4,5,6,7,8,9,24)) as EditEvents,
         min(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6)) as FirstEditDate,
         max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6)) as LastEditDate,
         count(*) filter (where ph.PostHistoryTypeId in (10)) as CloseVotesRecorded,
         count(*) filter (where ph.PostHistoryTypeId in (11)) as ReopenVotesRecorded
  from PostHistory ph
  group by ph.PostId
),
q_badges as (
  select b.UserId,
         count(*) as TotalBadges,
         count(*) filter (where b.Class = 1) as GoldBadges,
         count(*) filter (where b.Class = 2) as SilverBadges,
         count(*) filter (where b.Class = 3) as BronzeBadges,
         count(*) filter (where b.TagBased = 1) as TagBadges
  from Badges b
  group by b.UserId
),
tag_x as (
  select
    q.QuestionId,
    unnest(string_to_array(substring(coalesce(q.Tags,''), 2, greatest(length(coalesce(q.Tags,'')) - 2, 0)), '><')) as TagName
  from q
),
tag_stats as (
  select tx.QuestionId,
         t.TagName,
         t.Count as GlobalTagCount,
         dense_rank() over (partition by tx.QuestionId order by t.Count desc nulls last, t.TagName) as TagPopularityRank
  from tag_x tx
  left join Tags t
    on lower(tx.TagName) = lower(t.TagName)
),
tag_top as (
  select QuestionId,
         string_agg(TagName, ', ' order by TagPopularityRank, TagName) as TopTagsOrdered,
         max(GlobalTagCount) as MaxTagCount
  from tag_stats
  where TagPopularityRank <= 3 or TagPopularityRank is null
  group by QuestionId
),
answers_ranked as (
  select
    a.QuestionId,
    a.AnswerId,
    a.AnswerOwnerId,
    a.AnswerScore,
    a.AnswerCreationDate,
    row_number() over (partition by a.QuestionId order by a.AnswerScore desc nulls last, a.AnswerCreationDate asc, a.AnswerId) as AnswerRankByScore,
    row_number() over (partition by a.QuestionId order by a.AnswerCreationDate asc, a.AnswerId) as AnswerRankByTime
  from a
),
accepted as (
  select q.QuestionId, q.AcceptedAnswerId
  from q
  where q.AcceptedAnswerId is not null
),
first_last_answer as (
  select
    ar.QuestionId,
    min(ar.AnswerCreationDate) as FirstAnswerDate,
    max(ar.AnswerCreationDate) as LastAnswerDate,
    count(*) as TotalAnswers,
    sum(case when ar.AnswerScore > 0 then 1 else 0 end) as PositiveAnswers
  from answers_ranked ar
  group by ar.QuestionId
),
owner_activity as (
  select
    q.QuestionId,
    q.OwnerUserId,
    u.DisplayName as OwnerDisplayName,
    u.Reputation as OwnerReputation,
    u.UpVotes as OwnerUpVotes,
    u.DownVotes as OwnerDownVotes,
    qb.TotalBadges as OwnerTotalBadges,
    qb.GoldBadges as OwnerGoldBadges,
    qb.TagBadges as OwnerTagBadges,
    (u.UpVotes - u.DownVotes) as OwnerNetVotes,
    case when u.WebsiteUrl is null then 0 else 1 end as HasWebsite
  from q
  left join u on u.UserId = q.OwnerUserId
  left join q_badges qb on qb.UserId = q.OwnerUserId
),
question_health as (
  select
    q.QuestionId,
    q.Score,
    q.ViewCount,
    q.CreationDate,
    q.AnswerCount,
    coalesce(qv.NetVotes, 0) as NetVotes,
    coalesce(qv.UpvoteCount, 0) as UpvoteCount,
    coalesce(qv.DownvoteCount, 0) as DownvoteCount,
    coalesce(qv.FavoriteCount, 0) as FavoriteCount,
    coalesce(c.CommentCount, 0) as CommentCount,
    c.LastCommentDate,
    coalesce(c.CommentKudos, 0) as CommentKudos,
    coalesce(ql.LinkedCount, 0) as LinkedCount,
    coalesce(ql.DuplicateCount, 0) as DuplicateCount,
    coalesce(qe.EditEvents, 0) as EditEvents,
    qe.FirstEditDate,
    qe.LastEditDate
  from q
  left join q_votes qv on qv.PostId = q.QuestionId
  left join c on c.PostId = q.QuestionId
  left join q_links ql on ql.PostId = q.QuestionId
  left join q_edits qe on qe.PostId = q.QuestionId
),
penalties as (
  select
    QuestionId,
    case when DuplicateCount > 0 then 1 else 0 end as IsDuplicateFlag,
    case when Score < 0 then 1 else 0 end as IsNegativeScore,
    case when EditEvents > 10 then 1 else 0 end as IsChurny,
    greatest(0, DuplicateCount * 5 + (DownvoteCount * 2) - least(UpvoteCount, 10)) as HeuristicPenalty
  from question_health
  join q_votes using (PostId) -- PostId alias from q_votes; align with QuestionId via rename
),
accept_info as (
  select
    q.QuestionId,
    case when q.AcceptedAnswerId is not null then 1 else 0 end as HasAccepted,
    ai.AnswerScore as AcceptedAnswerScore,
    ai.AnswerCreationDate as AcceptedAnswerDate
  from q
  left join answers_ranked ai
    on ai.AnswerId = q.AcceptedAnswerId
),
response_times as (
  select
    q.QuestionId,
    fl.FirstAnswerDate,
    fl.LastAnswerDate,
    extract(epoch from (fl.FirstAnswerDate - q.CreationDate)) as SecondsToFirstAnswer,
    extract(epoch from (fl.LastAnswerDate - q.CreationDate)) as SecondsToLastAnswer
  from q
  left join first_last_answer fl on fl.QuestionId = q.QuestionId
),
complex_score as (
  select
    qh.QuestionId,
    -- Composite score mixing normalized components with weights
    (
      coalesce( (qh.Score)::numeric, 0)
      + coalesce( (qh.NetVotes)::numeric, 0) * 0.7
      + coalesce( (qh.FavoriteCount)::numeric, 0) * 0.5
      + coalesce( log(greatest(1, qh.ViewCount))::numeric, 0) * 1.2
      + coalesce( (qh.CommentKudos)::numeric, 0) * 0.3
      - coalesce( (qh.DuplicateCount)::numeric, 0) * 5
      - coalesce( (qh.DownvoteCount)::numeric, 0) * 0.8
    ) as RawComposite,
    coalesce( (qh.AnswerCount)::numeric, 0) as AnswerCountN,
    qh.UpvoteCount,
    qh.DownvoteCount
  from question_health qh
),
zscore as (
  select
    cs.QuestionId,
    cs.RawComposite,
    case
      when stddev_pop(cs.RawComposite) over () = 0 then 0
      else (cs.RawComposite - avg(cs.RawComposite) over ()) / nullif(stddev_pop(cs.RawComposite) over (), 0)
    end as ZComposite
  from complex_score cs
),
ranked as (
  select
    q.QuestionId,
    q.Title,
    coalesce(tt.TopTagsOrdered, '(no tags)') as TopTags,
    o.OwnerDisplayName,
    o.OwnerReputation,
    o.OwnerNetVotes,
    o.OwnerTotalBadges,
    o.HasWebsite,
    qh.Score,
    qh.ViewCount,
    qh.NetVotes,
    qh.UpvoteCount,
    qh.DownvoteCount,
    qh.FavoriteCount,
    qh.CommentCount,
    qh.LinkedCount,
    qh.DuplicateCount,
    qh.EditEvents,
    ai.HasAccepted,
    ai.AcceptedAnswerScore,
    rt.SecondsToFirstAnswer,
    rt.SecondsToLastAnswer,
    zs.ZComposite,
    row_number() over (
      order by
        coalesce(ai.HasAccepted,0) desc,
        coalesce(zs.ZComposite, -1e9) desc,
        qh.ViewCount desc,
        qh.Score desc,
        q.QuestionId desc
    ) as GlobalRank
  from q
  left join tag_top tt on tt.QuestionId = q.QuestionId
  left join owner_activity o on o.QuestionId = q.QuestionId
  left join question_health qh on qh.QuestionId = q.QuestionId
  left join accept_info ai on ai.QuestionId = q.QuestionId
  left join response_times rt on rt.QuestionId = q.QuestionId
  left join zscore zs on zs.QuestionId = q.QuestionId
),
comment_snippets as (
  select
    q.Id as QuestionId,
    string_agg(
      case
        when length(c.Text) > 80 then substring(c.Text, 1, 77) || '...'
        else c.Text
      end,
      ' | ' order by c.Score desc nulls last, c.CreationDate desc
    ) as TopCommentSnippets
  from Posts q
  left join Comments c on c.PostId = q.Id
  where q.PostTypeId = 1
  group by q.Id
),
duplicates_detail as (
  select
    pl.PostId as QuestionId,
    count(*) as DuplicateLinks,
    string_agg(distinct cast(pl.RelatedPostId as varchar), ', ' order by pl.RelatedPostId) as DuplicateOfIds
  from PostLinks pl
  where pl.LinkTypeId = 3
  group by pl.PostId
)
select
  r.GlobalRank,
  r.QuestionId,
  r.Title,
  r.TopTags,
  r.OwnerDisplayName,
  r.OwnerReputation,
  r.OwnerNetVotes,
  r.OwnerTotalBadges,
  case when r.HasWebsite = 1 then 'Y' else 'N' end as OwnerHasWebsite,
  r.Score,
  r.ViewCount,
  r.NetVotes,
  r.UpvoteCount,
  r.DownvoteCount,
  r.FavoriteCount,
  r.CommentCount,
  r.LinkedCount,
  r.DuplicateCount,
  r.EditEvents,
  r.HasAccepted,
  r.AcceptedAnswerScore,
  coalesce(round(r.SecondsToFirstAnswer/3600.0, 2), null) as HoursToFirstAnswer,
  coalesce(round(r.SecondsToLastAnswer/3600.0, 2), null) as HoursToLastAnswer,
  round(coalesce(r.ZComposite, 0)::numeric, 3) as ZComposite,
  coalesce(cs.TopCommentSnippets, '') as TopCommentSnippets,
  coalesce(dd.DuplicateLinks, 0) as DuplicateLinks,
  coalesce(dd.DuplicateOfIds, '') as DuplicateOfIds
from ranked r
left join comment_snippets cs on cs.QuestionId = r.QuestionId
left join duplicates_detail dd on dd.QuestionId = r.QuestionId
where
  -- Complex predicate combining multiple factors and NULL handling
  (
    (r.HasAccepted = 1 and r.ViewCount >= 100)
    or (r.HasAccepted = 0 and r.ViewCount >= 1000 and coalesce(r.EditEvents,0) >= 1)
    or (r.HasAccepted is null and r.Score >= 5 and r.NetVotes >= 5)
  )
  and coalesce(r.DuplicateCount, 0) <= 5
  and (r.TopTags not ilike '%off-topic%' or r.TopTags is null)
  and (r.OwnerReputation is null or r.OwnerReputation >= 100)
order by r.GlobalRank
limit 200;