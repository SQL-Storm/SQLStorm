-- {"query": "2245.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1277} 
with RankedAnswers as (
  select
    p.Id,
    p.ParentId,
    p.Score,
    p.CreationDate,
    u.Id as UserId,
    u.DisplayName,
    row_number() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as rn
  from Posts p
  left join Users u on p.OwnerUserId = u.Id
  where p.PostTypeId = 2
),
QuestionStats as (
  select 
    q.Id as QuestionId,
    q.Title,
    q.Tags,
    q.Score as QuestionScore,
    q.ViewCount,
    q.CreationDate,
    q.AcceptedAnswerId,
    u.Id as OwnerUserId,
    u.DisplayName as OwnerDisplayName,
    coalesce(bd.GoldBadges,0) as GoldBadges,
    coalesce(bd.SilverBadges,0) as SilverBadges,
    coalesce(bd.BronzeBadges,0) as BronzeBadges
  from Posts q
  left join Users u on q.OwnerUserId = u.Id
  left join (
    select
      UserId,
      sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
      sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
      sum(case when Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges
    group by UserId
  ) bd on bd.UserId = u.Id
  where q.PostTypeId = 1
),
AnswerWithComments as (
  select
    ra.Id as AnswerId,
    ra.ParentId as QuestionId,
    ra.Score,
    ra.CreationDate,
    ra.UserId,
    ra.DisplayName,
    coalesce(cmt.CommentCount,0) as CommentCount,
    coalesce(cmt.AvgCommentLength,0) as AvgCommentLength
  from RankedAnswers ra
  left join (
    select
      PostId,
      count(*) as CommentCount,
      avg(length(Text)) as AvgCommentLength
    from Comments
    group by PostId
  ) cmt on cmt.PostId = ra.Id
  where ra.rn <= 3
),
DuplicateLinks as (
  select
    pl.PostId as DuplicateQuestionId,
    pl.RelatedPostId as OriginalQuestionId,
    ltype.Name as LinkTypeName
  from PostLinks pl
  join LinkTypes ltype on ltype.Id = pl.LinkTypeId
  where pl.LinkTypeId = 3
),
CTEWithSubqueries as (
  select
    qs.QuestionId,
    qs.Title,
    qs.Tags,
    qs.QuestionScore,
    qs.ViewCount,
    qs.CreationDate as QuestionCreation,
    qs.AcceptedAnswerId,
    qs.OwnerUserId,
    qs.OwnerDisplayName,
    qs.GoldBadges,
    qs.SilverBadges,
    qs.BronzeBadges,
    a.CommentCount as TopAnswerComments,
    a.AvgCommentLength as TopAnswerAvgCommentLen,
    case 
      when dup.DuplicateQuestionId is not null then 'Yes' 
      else 'No' 
    end as IsDuplicate,
    dup.OriginalQuestionId,
    (select count(1) 
     from Posts ans 
     where ans.ParentId = qs.QuestionId and ans.PostTypeId = 2
    ) as TotalAnswers,
    (select count(distinct UserId) 
     from Votes v2 
     where v2.PostId = qs.QuestionId and v2.VoteTypeId = 2
    ) as UniqueUpvoters,
    (select max(p2.Score) 
     from Posts p2 
     where p2.ParentId = qs.QuestionId and p2.PostTypeId = 2
    ) as MaxAnswerScore
  from QuestionStats qs
  left join AnswerWithComments a on a.QuestionId = qs.QuestionId
    and a.Score = (
      select max(score) from RankedAnswers where ParentId = qs.QuestionId
    )
  left join DuplicateLinks dup on dup.DuplicateQuestionId = qs.QuestionId
),
RankedQuestions as (
  select *,
    dense_rank() over (order by QuestionScore desc, ViewCount desc) as RankByScoreView
  from CTEWithSubqueries
)
select 
  rq.RankByScoreView,
  rq.QuestionId,
  substring(rq.Title, 1, 100) as SnippetTitle,
  regexp_replace(rq.Tags, '[<>]', ',', 'g') as TagsList,
  rq.QuestionScore,
  rq.ViewCount,
  rq.GoldBadges,
  rq.SilverBadges,
  rq.BronzeBadges,
  coalesce(rq.TotalAnswers,0) as TotalAnswers,
  coalesce(rq.UniqueUpvoters,0) as UniqueUpvoters,
  rq.MaxAnswerScore,
  rq.TopAnswerComments,
  rq.TopAnswerAvgCommentLen,
  rq.IsDuplicate,
  rq.OriginalQuestionId,
  case 
    when rq.TotalAnswers = 0 then null
    else round(rq.QuestionScore::numeric / rq.TotalAnswers, 3)
  end as ScorePerAnswer,
  case 
    when lower(rq.IsDuplicate) = 'yes' then 
      concat('Duplicate of question ID ', rq.OriginalQuestionId)
    else 'Original question'
  end as DuplicateStatus,
  case 
    when rq.GoldBadges + rq.SilverBadges + rq.BronzeBadges > 10 then 'High badge holder'
    when rq.GoldBadges + rq.SilverBadges + rq.BronzeBadges between 5 and 10 then 'Medium badge holder'
    else 'Low badge holder'
  end as BadgeHolderLevel
from RankedQuestions rq
where rq.CreationDate > current_date - interval '1 year'
  and (rq.QuestionScore > 10 or rq.ViewCount > 1000)
order by rq.RankByScoreView
limit 50;