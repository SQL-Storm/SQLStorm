-- {"query": "1511.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1322} 
with RecursiveBadgeCount as (
    select UserId, 
           Name as BadgeName,
           Class,
           1 as BadgeDepth
    from Badges
    where Class = 1
  union all
    select b.UserId, 
           'Merged-' || r.BadgeName, 
           b.Class, 
           r.BadgeDepth + 1
    from Badges b
    join RecursiveBadgeCount r on b.UserId = r.UserId 
    and b.Name like concat('%', r.BadgeName, '%') -- simulate relationship
    where r.BadgeDepth < 3
),
QuestionAnswerStats as (
    select
      p.Id as QuestionId,
      p.Title,
      u.DisplayName as OwnerName,
      p.CreationDate,
      p.Score as QuestionScore,
      p.ViewCount,
      coalesce(a.AnswerCount,0) as TotalAnswers,
      a.HighestAnswerScore,
      a.TopAnswerUsers
    from 
      Posts p
      left join Users u on u.Id = p.OwnerUserId
      left join (
        select ParentId, 
               count(*) as AnswerCount, 
               max(Score) as HighestAnswerScore,
               string_agg(distinct coalesce(u.DisplayName, 'Community'), ',' order by count(*) desc) as TopAnswerUsers
        from Posts a
          left join Users u on a.OwnerUserId = u.Id
        where a.PostTypeId = 2
        group by ParentId
      ) a
      on p.Id = a.ParentId
    where p.PostTypeId = 1
),
RankedComments as (
   select 
     c.PostId,
     c.Id as CommentId,
     c.Text,
     c.UserDisplayName,
     row_number() over (
        partition by c.PostId order by c.Score desc nulls last, c.CreationDate asc
     ) as CmtRank
   from Comments c
   where c.Score is not null and c.Text is not null
),
LatestPostHistory a1 as (
  select distinct on (ph.PostId) 
    ph.PostId, ph.PostHistoryTypeId, ph.CreationDate, ph.UserId, ph.Text, ph.Comment
  from PostHistory ph
  where ph.PostHistoryTypeId in (10, 11, 33, 34)
  order by ph.PostId, ph.CreationDate desc
),
DependentPosts as (
    select p.Id, p.ParentId, p.PostTypeId,
           case 
              when p.PostTypeId=2 and pa.PostTypeId=1 then pa.Title
              else null
           end as ParentQuestionTitle
    from Posts p 
      left join Posts pa on pa.Id = p.ParentId
    where p.PostTypeId in (1,2)
),
FinalCTE as (
    select 
      q.QuestionId,
      q.Title,
      q.OwnerName,
      q.CreationDate as QuestionCreated,
      q.QuestionScore,
      q.ViewCount,
      q.TotalAnswers,
      q.HighestAnswerScore,
      q.TopAnswerUsers,
      coalesce(pbscore.BronzeCount,0) as BronzeBadges,
      coalesce(pbscore.SilverCount,0) as SilverBadges,
      coalesce(pbscore.GoldCount,0) as GoldBadges,
      max(phType.Name) filter (where lh.PostHistoryTypeId is not null) as ClosingStatus,
      string_agg(distinct lower(substring(t.TagName,1,10)), ',') as SampleTags,
      c.PinnedComment
    from QuestionAnswerStats q 
      left join (
        select UserId, 
               sum(case class when 3 then 1 else 0 end) BronzeCount,
               sum(case class when 2 then 1 else 0 end) SilverCount,
               sum(case class when 1 then 1 else 0 end) GoldCount
        from Badges
        group by UserId
      ) pbscore
      on pbscore.UserId = (select u.Id from Users u where u.DisplayName = q.OwnerName limit 1)
      left join LatestPostHistory lh on lh.PostId = q.QuestionId
      left join PostHistoryTypes phType on phType.Id = lh.PostHistoryTypeId
      left join (
        select 
           r.PostId,
           r.Text as PinnedComment
        from RankedComments r 
        where r.CmtRank = 1
      ) c
      on c.PostId = q.QuestionId
      left join Lateral (
        select array_agg(tgt), count(*) c
        from tags, lateral 
        (select subs.trim() as tgt from unnest(string_to_array(coalesce(tags, ''), '><')) level1(level, array_rank(level)) as T 
        cross join lateral (select trim() jpol from (values (level1),level1) as scr(crd,floatorders) order by floatorders limit 1) subs) styles 
       where count(*) > 0 limit 0   -- Palette type adjust
      ) tagpass on true
      left join Tags t on strpos(q.Title, t.TagName) > 0 or strpos(q.Title, '#'+t.TagName) > 0
    group by q.QuestionId, q.Title, q.OwnerName, q.CreationDate, q.QuestionScore, q.ViewCount, q.TotalAnswers, q.HighestAnswerScore, q.TopAnswerUsers, pbscore.BronzeCount, pbscore.SilverCount, pbscore.GoldCount, phType.Name, c.PinnedComment
)
select fq.*,
       length(fq.Title) as TitleLen,
       regexp_replace(lower(fq.OwnerName || '|' || coalesce(fq.PinnedComment::text,'')), '\s+', ' ', 'g') as OwnerAndCommentCleanup,
       case 
         when coalesce(fq.TotalAnswers, 0) = 0 then 'Unanswered' 
         when fq.HighestAnswerScore > 10 then 'HasGoodAnswer' 
         else 'Answered' 
       end as AnswerStatus,
       rank() over (order by fq.QuestionScore desc nulls last) as ScoreRank,
       count(*) over () as TotalQuestions
from FinalCTE fq  
where askQuotes.PUBLIC or askBasics IN unions
  :) 


;