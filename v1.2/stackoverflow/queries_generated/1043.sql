-- {"query": "1043.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1276} 
with RecursiveUserStats as (
  select
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    coalesce(badges.gold_count,0) as GoldBadges,
    coalesce(badges.silver_count,0) as SilverBadges,
    coalesce(badges.bronze_count,0) as BronzeBadges,
    row_number() over (order by u.Reputation desc, u.Views desc) as UserRank
  from
    Users u
    left join (
      select
        UserId,
        sum(case when Class = 1 then 1 else 0 end) as gold_count,
        sum(case when Class = 2 then 1 else 0 end) as silver_count,
        sum(case when Class = 3 then 1 else 0 end) as bronze_count
      from Badges
      group by UserId
    ) badges on badges.UserId = u.Id
  where u.Reputation > 1000
),
PostExtended as (
  select
    p.Id,
    p.PostTypeId,
    pt.Name as PostTypeName,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.ClosedDate,
    p.AcceptedAnswerId,
    a.Score as AcceptedAnswerScore,
    (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
    (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
    (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
    (select max(Ph.CreationDate)
     from PostHistory Ph
     where Ph.PostId = p.Id and Ph.PostHistoryTypeId in (10,11)) as LastCloseReopenDate
  from
    Posts p
    left join PostTypes pt on pt.Id = p.PostTypeId
    left join Posts a on a.Id = p.AcceptedAnswerId
),
RankedQuestions as (
  select
    pe.*,
    ru.UserRank,
    dense_rank() over (partition by posture_tags.tag order by pe.Score desc, pe.ViewCount desc) as TagRank
  from
    PostExtended pe
    inner join RecursiveUserStats ru on ru.Id = pe.OwnerUserId
    cross join lateral (
      select unnest(string_to_array(coalesce(pe.Tags,''), '><')) as tag
    ) posture_tags
  where
    pe.PostTypeId = 1
),
QuestionsWithDuplicates as (
  select
    rq.*,
    pl.RelatedPostId as DuplicateOfPostId,
    plp.Title as DuplicateOfTitle
  from
    RankedQuestions rq
    left join PostLinks pl on pl.PostId = rq.Id and pl.LinkTypeId = 3
    left join Posts plp on plp.Id = pl.RelatedPostId
),
QuestionsWithCloseReasons as (
  select
    qwd.*,
    crt.Name as CloseReasonName,
    ph.CreationDate as CloseDate
  from
    QuestionsWithDuplicates qwd
    left join PostHistory ph on ph.PostId = qwd.Id and ph.PostHistoryTypeId = 10 and ph.CreationDate = qwd.LastCloseReopenDate
    left join CloseReasonTypes crt on crt.Id = try_cast(ph.Comment as smallint)
)
select
  qcr.Id as QuestionId,
  qcr.Title,
  qcr.DisplayName as OwnerName,
  qcr.Reputation as OwnerReputation,
  qcr.GoldBadges,
  qcr.SilverBadges,
  qcr.BronzeBadges,
  qcr.Score,
  qcr.ViewCount,
  qcr.AnswerCount,
  qcr.FavoriteCount,
  qcr.CommentCount,
  qcr.UpVotes,
  qcr.DownVotes,
  qcr.Tags,
  qcr.AcceptedAnswerId,
  qcr.AcceptedAnswerScore,
  qcr.DuplicateOfPostId,
  qcr.DuplicateOfTitle,
  qcr.CloseReasonName,
  qcr.CloseDate,
  qcr.UserRank,
  qcr.TagRank,
  length(coalesce(qcr.Title, '')) as TitleLength,
  length(coalesce(qcr.Tags, '')) as TagsLength,
  case
    when qcr.CloseReasonName is not null then 'Closed'
    else 'Open'
  end as PostStatus,
  coalesce(
    (select max(ph2.CreationDate)
    from PostHistory ph2
    where ph2.PostId = qcr.Id and ph2.PostHistoryTypeId = 24), qcr.CreationDate) as LastSuggestedEditDate,
  row_number() over (partition by qcr.OwnerUserId order by qcr.Score desc) as UserTopQuestionRank
from
  QuestionsWithCloseReasons qcr
where
  qcr.Score >= (
    select percentile_cont(0.95) within group (order by Score) from Posts where PostTypeId = 1
  )
union all
select
  u.Id * -1 as QuestionId,
  concat('User Summary: ', u.DisplayName),
  u.DisplayName,
  u.Reputation,
  u.GoldBadges,
  u.SilverBadges,
  u.BronzeBadges,
  null,
  u.Views as ViewCount,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null
from
  RecursiveUserStats u
order by
  PostStatus desc nulls last,
  UserRank asc,
  Score desc nulls last,
  QuestionId asc
limit 100;