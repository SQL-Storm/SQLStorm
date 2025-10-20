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
    pe.Id,
    pe.PostTypeId,
    pe.PostTypeName,
    pe.OwnerUserId,
    pe.Score,
    pe.ViewCount,
    pe.AnswerCount,
    pe.FavoriteCount,
    pe.Tags,
    pe.CreationDate,
    pe.LastActivityDate,
    pe.ClosedDate,
    pe.AcceptedAnswerId,
    pe.AcceptedAnswerScore,
    pe.CommentCount,
    pe.UpVotes as PostUpVotes,
    pe.DownVotes as PostDownVotes,
    pe.LastCloseReopenDate,
    ru.UserRank,
    dense_rank() over (partition by posture_tags.tag order by pe.Score desc, pe.ViewCount desc) as TagRank,
    posture_tags.tag
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
    rq.Id,
    rq.PostTypeId,
    rq.PostTypeName,
    rq.OwnerUserId,
    rq.Score,
    rq.ViewCount,
    rq.AnswerCount,
    rq.FavoriteCount,
    rq.Tags,
    rq.CreationDate,
    rq.LastActivityDate,
    rq.ClosedDate,
    rq.AcceptedAnswerId,
    rq.AcceptedAnswerScore,
    rq.CommentCount,
    rq.PostUpVotes,
    rq.PostDownVotes,
    rq.LastCloseReopenDate,
    rq.UserRank,
    rq.TagRank,
    rq.tag,
    pl.RelatedPostId as DuplicateOfPostId,
    plp.Title as DuplicateOfTitle
  from
    RankedQuestions rq
    left join PostLinks pl on pl.PostId = rq.Id and pl.LinkTypeId = 3
    left join Posts plp on plp.Id = pl.RelatedPostId
),
QuestionsWithCloseReasons as (
  select
    qwd.Id,
    qwd.PostTypeId,
    qwd.PostTypeName,
    qwd.OwnerUserId,
    qwd.Score,
    qwd.ViewCount,
    qwd.AnswerCount,
    qwd.FavoriteCount,
    qwd.Tags,
    qwd.CreationDate,
    qwd.LastActivityDate,
    qwd.ClosedDate,
    qwd.AcceptedAnswerId,
    qwd.AcceptedAnswerScore,
    qwd.CommentCount,
    qwd.PostUpVotes,
    qwd.PostDownVotes,
    qwd.LastCloseReopenDate,
    qwd.UserRank,
    qwd.TagRank,
    qwd.tag,
    qwd.DuplicateOfPostId,
    qwd.DuplicateOfTitle,
    crt.Name as CloseReasonName,
    ph.CreationDate as CloseDate
  from
    QuestionsWithDuplicates qwd
    left join PostHistory ph on ph.PostId = qwd.Id and ph.PostHistoryTypeId = 10 and ph.CreationDate = qwd.LastCloseReopenDate
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as smallint)
)
select
  qcr.Id as QuestionId,
  qcr.DuplicateOfTitle as Title, -- original source had qcr.Title which doesn't exist; use DuplicateOfTitle or Posts.Title if available
  ru.DisplayName as OwnerName,
  ru.Reputation as OwnerReputation,
  ru.GoldBadges,
  ru.SilverBadges,
  ru.BronzeBadges,
  qcr.Score,
  qcr.ViewCount,
  qcr.AnswerCount,
  qcr.FavoriteCount,
  qcr.CommentCount,
  qcr.PostUpVotes as UpVotes,
  qcr.PostDownVotes as DownVotes,
  qcr.Tags,
  qcr.AcceptedAnswerId,
  qcr.AcceptedAnswerScore,
  qcr.DuplicateOfPostId,
  qcr.DuplicateOfTitle,
  qcr.CloseReasonName,
  qcr.CloseDate,
  qcr.UserRank,
  qcr.TagRank,
  length(coalesce(qcr.DuplicateOfTitle, '')) as TitleLength,
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
  left join RecursiveUserStats ru on ru.Id = qcr.OwnerUserId
where
  qcr.Score >= (
    select percentile_cont(0.95) within group (order by Score) from Posts where PostTypeId = 1
  )
union all
select
  u.Id * -1 as QuestionId,
  ('User Summary: ' || u.DisplayName) as Title,
  u.DisplayName,
  u.Reputation,
  u.GoldBadges,
  u.SilverBadges,
  u.BronzeBadges,
  null as Score,
  u.Views as ViewCount,
  null as AnswerCount,
  null as FavoriteCount,
  null as CommentCount,
  null as UpVotes,
  null as DownVotes,
  null as Tags,
  null as AcceptedAnswerId,
  null as AcceptedAnswerScore,
  null as DuplicateOfPostId,
  null as DuplicateOfTitle,
  null as CloseReasonName,
  null as CloseDate,
  u.UserRank,
  null as TagRank,
  length(coalesce('User Summary: ' || u.DisplayName, '')) as TitleLength,
  0 as TagsLength,
  'Open' as PostStatus,
  null as LastSuggestedEditDate,
  null as UserTopQuestionRank
from
  RecursiveUserStats u
order by
  PostStatus desc,
  UserRank asc,
  Score desc,
  QuestionId asc
limit 100;