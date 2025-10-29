with recursive RecursivePostParents as (
    select
        p.Id,
        p.ParentId,
        1 as Level,
        array[p.Id] as Ancestors
    from Posts p
    where p.ParentId is null
    union all
    select
        p.Id,
        p.ParentId,
        r.Level + 1,
        r.Ancestors || array[p.Id]
    from Posts p
    join RecursivePostParents r on p.ParentId = r.Id
    where not p.Id = any(r.Ancestors)
),
UserBadgesAgg as (
    select
        b.UserId,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
TopPosters as (
    select
        u.Id,
        u.DisplayName,
        count(p.Id) as TotalPosts,
        sum(p.Score) as TotalScore,
        rank() over (order by sum(p.Score) desc) as ScoreRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId in (1, 2)
    group by u.Id, u.DisplayName
    having count(p.Id) > 10
),
LatestCommentsPerPost as (
    select
        c.PostId,
        c.Id as CommentId,
        c.Text as CommentText,
        c.CreationDate as CommentDate,
        c.UserDisplayName as CommentAuthor
    from (
        select
            c.*,
            row_number() over (partition by c.PostId order by c.CreationDate desc) as rn
        from Comments c
    ) c
    where c.rn = 1
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate as QuestionDate,
        a.Id as AnswerId,
        a.OwnerUserId as AnswerOwnerUserId,
        a.CreationDate as AnswerDate,
        a.Score as AnswerScore,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
HighScoringAnswersWithDuplicates as (
    select
        qa.QuestionId,
        qa.AnswerId,
        qa.AnswerScore,
        l.Id as LinkId,
        l.LinkTypeId,
        lt.Name as LinkTypeName,
        dup.Id as DuplicateQuestionId,
        dup.Title as DuplicateQuestionTitle
    from QuestionAnswerStats qa
    left join PostLinks l on l.PostId = qa.QuestionId and l.LinkTypeId = 3
    left join Posts dup on dup.Id = l.RelatedPostId and dup.PostTypeId = 1
    left join LinkTypes lt on lt.Id = l.LinkTypeId
    where qa.AnswerScore > 10
),
TopTagsWithStats as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(qs.QuestionCount, 0) as QuestionCount,
        coalesce(avgAnswerStats.AvgAnswerScore, 0) as AvgAnswerScore
    from Tags t
    left join (
        select
            tag as TagName,
            count(*) as QuestionCount
        from (
            select unnest(string_to_array(trim(both '<>' from p.Tags), '><')) as tag
            from Posts p
            where p.PostTypeId = 1
        ) x
        group by tag
    ) qs on qs.TagName = t.TagName
    left join (
        select
            tag as TagName,
            avg(a.Score) as AvgAnswerScore
        from (
            select p.Id, unnest(string_to_array(trim(both '<>' from p.Tags), '><')) as tag
            from Posts p
            where p.PostTypeId = 1
        ) pq
        join Posts a on a.ParentId = pq.Id and a.PostTypeId = 2
        group by tag
    ) avgAnswerStats on avgAnswerStats.TagName = t.TagName
    where t.Count > 1000
)
select 
    p.Id as PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    coalesce(u.DisplayName, 'Community') as OwnerName,
    uba.GoldBadges,
    uba.SilverBadges,
    uba.BronzeBadges,
    coalesce(tc.CommentText, '[No Comments]') as LatestComment,
    qas.AnswerId,
    qas.AnswerScore,
    case 
        when dupq.DuplicateQuestionId is not null then 'Duplicate of: ' || dupq.DuplicateQuestionTitle
        else 'No duplicate'
    end as DuplicateStatus,
    tts.TagName,
    tts.QuestionCount,
    round(cast(tts.AvgAnswerScore as numeric), 2) as AverageAnswerScore,
    row_number() over (partition by p.Id order by qas.AnswerScore desc) as AnswerRank,
    (
      case when p.ClosedDate is not null then 'Closed' else 'Open' end
      || ' | ' ||
      case when p.FavoriteCount > 0 then cast(p.FavoriteCount as varchar) || ' favorites' else 'No favorites' end
      || ' | ' ||
      case when p.ViewCount > 1000 then 'Popular (' || cast(p.ViewCount as varchar) || ' views)' else 'Less popular' end
    ) as StatusSummary
from Posts p
left join Users u on u.Id = p.OwnerUserId
left join UserBadgesAgg uba on uba.UserId = u.Id
left join LatestCommentsPerPost tc on tc.PostId = p.Id
left join QuestionAnswerStats qas on qas.QuestionId = p.Id and qas.AnswerRank = 1
left join HighScoringAnswersWithDuplicates dupq on dupq.AnswerId = qas.AnswerId
left join TopTagsWithStats tts on tts.TagName = any(string_to_array(trim(both '<>' from p.Tags), '><'))
where p.PostTypeId = 1
  and (p.Score > 5 or p.FavoriteCount > 0 or p.ViewCount > 500)
group by
    p.Id,
    p.Title,
    p.CreationDate,
    p.Score,
    u.DisplayName,
    uba.GoldBadges,
    uba.SilverBadges,
    uba.BronzeBadges,
    tc.CommentText,
    qas.AnswerId,
    qas.AnswerScore,
    dupq.DuplicateQuestionId,
    dupq.DuplicateQuestionTitle,
    tts.TagName,
    tts.QuestionCount,
    tts.AvgAnswerScore,
    p.ClosedDate,
    p.FavoriteCount,
    p.ViewCount
order by p.Score desc, p.CreationDate desc
limit 100;