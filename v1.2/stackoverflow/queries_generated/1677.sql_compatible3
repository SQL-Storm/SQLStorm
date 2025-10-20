with recursive Recursive_TagParents as (
    select 
        t.Id,
        t.TagName,
        pl.RelatedPostId as ParentPostId,
        p.Title as ParentTitle
    from Tags t
    join PostLinks pl on pl.PostId = t.ExcerptPostId and pl.LinkTypeId = 1
    join Posts p on p.Id = pl.RelatedPostId

    union all

    select 
        rtp.Id,
        rtp.TagName,
        pl.RelatedPostId,
        p.Title
    from Recursive_TagParents rtp
    join PostLinks pl on pl.PostId = rtp.ParentPostId and pl.LinkTypeId = 1
    join Posts p on p.Id = pl.RelatedPostId
    where pl.RelatedPostId is not null
),
TagWithScoreAndPop as (
    select 
        t.Id, 
        t.TagName,
        t.Count as TagCount, 
        length(t.TagName) as TagLength,
        string_agg(DISTINCT postfix.Val, ',') as Customs,
        row_number() over(partition by t.Id order by t.Count desc) as rn
    from Tags t
    left join lateral (
        select unnest(string_to_array(substring(p.Tags from 2 for coalesce(NULLIF(length(p.Tags)-2, -1),0)), '><')) as Val
        from Posts p 
        where p.PostTypeId = 1 and p.Id = t.ExcerptPostId
        limit 100
    ) postfix on true
    group by t.Id, t.TagName, t.Count
),
UserQuestionsInfo as (
    select 
        u.Id as UserId,
        u.DisplayName,
        coalesce(count(distinct q.Id), 0) as TotalQuestions,                
        coalesce(sum(case when q.Score > 10 then 1 else 0 end), 0) as PopularQuestions_count,       
        max(case when q.PostTypeId = 1 then q.ViewCount end) as MostViewedQuestion_views,
        min(case when q.PostTypeId = 1 then q.CreationDate end) as FirstQuestionDate,
        max(case when q.PostTypeId = 1 then q.CreationDate end) as LastQuestionDate,
        bool_or(u.WebsiteUrl is not null and length(u.WebsiteUrl) > 10) as HasLongWebsites
    from Users u
    left join Posts q on q.OwnerUserId = u.Id and q.PostTypeId = 1
    group by u.Id, u.DisplayName
),
AnswersRanks as (
    select
      a.Id,
      a.OwnerUserId,
      a.ParentId as question_id,
      rank() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) as AnswerRank,
      lead(a.CreationDate) OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) as NextAnswerCreationDate
    from Posts a
    where a.PostTypeId = 2
)
select
    tsp.Id,
    tsp.TagName,
    tsp.TagCount,
    tsp.TagLength,
    tsp.Customs,
    tsp.rn,
    rtp.ParentPostId,
    rtp.ParentTitle,
    uqi.UserId,
    uqi.DisplayName,
    uqi.TotalQuestions,
    uqi.PopularQuestions_count,
    uqi.MostViewedQuestion_views,
    uqi.FirstQuestionDate,
    uqi.LastQuestionDate,
    uqi.HasLongWebsites,
    ar.Id as AnswerId,
    ar.OwnerUserId as AnswerOwnerUserId,
    ar.question_id,
    ar.AnswerRank,
    ar.NextAnswerCreationDate
from TagWithScoreAndPop tsp
join Recursive_TagParents rtp on rtp.Id = tsp.Id
left join UserQuestionsInfo uqi on uqi.UserId = tsp.Id
left join AnswersRanks ar on ar.question_id = rtp.ParentPostId
where tsp.rn = 1;