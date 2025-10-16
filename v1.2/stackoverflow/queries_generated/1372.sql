-- {"query": "1372.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1418} 
with RecursiveTagCounts as (
    select t.Id, t.TagName, t.Count, coalesce(ti.TotalQuestions,0) as TotalQuestions,
           coalesce(cq.CommentCount,0) as CommentCountOnQuestions,
           coalesce(ca.CommentCount,0) as CommentCountOnAnswers
    from Tags t
    left join (
        select Posts.Id, count(*) as TotalQuestions 
        from Posts
        where PostTypeId = 1
        group by Posts.Id
    ) ti on ti.Id = t.ExcerptPostId
    left join (
        select p.Id, sum(c.CommentCount) as CommentCount 
        from Posts p 
        left join (
            select PostId, count(*) as CommentCount 
            from Comments 
            group by PostId
        ) c on p.Id = c.PostId
        where p.PostTypeId = 1
        group by p.Id
    ) cq on cq.Id = t.ExcerptPostId
    left join (
        select p.Id, sum(c.CommentCount) as CommentCount 
        from Posts p 
        left join (
            select PostId, count(*) as CommentCount 
            from Comments 
            group by PostId
        ) c on p.Id = c.PostId
        where p.PostTypeId = 2
        group by p.Id
    ) ca on ca.Id = t.WikiPostId
), AnswerStats as (
    select p.ParentId as QuestionId,
        count(p.Id) as TotalAnswers,
        sum(case when p.Score > 10 then 1 else 0 end) as HighScoreAnswers,
        avg(coalesce(p.Score,0)) as AvgAnswerScore,
        max(coalesce(p.CreationDate,'1970-01-01')) as LatestAnswerDate
    from Posts p
    where p.PostTypeId = 2
    group by p.ParentId
), UserBadgeCounts as (
    select u.Id as UserId,
           count(b.Id) filter (where b.Class = 1) as GoldBadges,
           count(b.Id) filter (where b.Class = 2) as SilverBadges,
           count(b.Id) filter (where b.Class = 3) as BronzeBadges,
           count(b.Id) filter (where b.TagBased = 1) as TagBasedBadges
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id
), LatestPostActivity as (
    select p.Id,
      p.Title,
      p.Tags,
      p.OwnerUserId,
      p.PostTypeId,
      LEAD(p.LastActivityDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) as NextActivityDate,
      p.LastActivityDate,
      p.Score,
      p.ViewCount,
      coalesce((select count(*) from Comments where PostId = p.Id),0) as CommentCount,
      coalesce((select count(*) from Votes where PostId = p.Id and VoteTypeId=2),0) as UpVotes
    from Posts p
    where p.PostTypeId in (1,2)
), Duplicates as (
    select pl.PostId, pl.RelatedPostId
    from PostLinks pl
    where pl.LinkTypeId = 3 -- duplicate link
), QuestionsWithDuplicates as (
    select p.Id as QuestionId,
           count(distinct d.RelatedPostId) as DuplicateCount,
           min(d.RelatedPostId) as ExampleDuplicateId
    from Posts p
    left join Duplicates d on p.Id = d.PostId
    where p.PostTypeId = 1
    group by p.Id
)
select q.Id as QuestionId,
       q.Title,
       q.CreationDate,
       q.Score as QuestionScore,
       decorateTagList(q.Tags) as DecoratedTags,
       coalesce(as0.TotalAnswers, 0) as TotalAnswers,
       coalesce(as0.HighScoreAnswers, 0) as HighScoreAnswers,
       coalesce(as0.AvgAnswerScore, 0) as AverageAnswerScore,
       coalesce(u.BadgeSummary, 'No badges') as BadgeSummary,
       lub.LatestUserActivity,
       qwc.DuplicateCount,
       qwc.ExampleDuplicateId,
       case when q.AcceptedAnswerId is not null then 'Yes' else 'No' end as HasAcceptedAnswer,
       case 
           when V.UpVotes > 100 then 'Popular' 
           when V.UpVotes between 20 and 100 then 'Moderate' 
           else 'Low' 
       end as Popularity
from Posts q
inner join AnswerStats as0 on as0.QuestionId = q.Id
left join (
    select ub.UserId, 
           format(
             'Gold: %s, Silver: %s, Bronze: %s, TagBased: %s',
              coalesce(ub.GoldBadges, 0), 
              coalesce(ub.SilverBadges, 0),
              coalesce(ub.BronzeBadges, 0), 
              coalesce(ub.TagBasedBadges, 0)
           ) as BadgeSummary
    from UserBadgeCounts ub
) u on u.UserId = q.OwnerUserId
left join (
    select lpa.OwnerUserId,
           max(lpa.LastActivityDate) as LatestUserActivity
    from LatestPostActivity lpa
    group by lpa.OwnerUserId
) lub on lub.OwnerUserId = q.OwnerUserId
left join QuestionsWithDuplicates qwc on qwc.QuestionId = q.Id
left join LatestPostActivity V on V.Id = q.Id
where q.PostTypeId = 1
and ( 
    q.Score > (select avg(Score) from Posts where PostTypeId = 1) 
    or as0.HighScoreAnswers > 0
)
and (
    length(trim(coalesce(q.Title, ''))) > 20
    and q.CreationDate > '2018-01-01'
)
order by q.Score desc, as0.TotalAnswers desc
limit 100
; 

-- function showing a complicated string splitting/tags decoration example
create or replace function decorateTagList(inputTags varchar) returns varchar as $$
declare 
    tags varchar[];
    decoratedTags varchar = '{}';
    tag varchar;
begin
    if inputTags is null then return null; end if;
    tags := string_to_array(substring(inputTags from 2 for length(inputTags)-2),'><');
    foreach tag in array tags loop
        decoratedTags := decoratedTags || format('[<a href="/tags/%s">%s</a>]', tag, tag);
    end loop;
    return array_to_string(decoratedTags, ' ');
end;
$$ language plpgsql immutable;