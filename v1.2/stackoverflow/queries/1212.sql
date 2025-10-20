-- {"query": "1212.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1558} 
with LatestPostEdits as (
    select ph.PostId,
           max(ph.CreationDate) as LastEditDate,
           max(case when ph.PostHistoryTypeId in (10, 11) then ph.Comment end) filter (where ph.PostHistoryTypeId in (10, 11)) as CloseReopenReason,
           count(*) over (partition by ph.PostId) as EditCount
    from PostHistory ph
    where ph.PostHistoryTypeId in (4, 5, 6, 10, 11) -- Title, Body, Tags edits + Close/Reopen
    group by ph.PostId
),
UserBadgesSummary as (
    select u.Id as UserId, u.DisplayName,
           count(distinct b.Id) as TotalBadges,
           sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
           sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
           sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
           bool_or(b.TagBased) as HasTagBadges
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName
),
QuestionAnswerStats as (
    select q.Id as QuestionId, q.Title, q.Tags, q.CreationDate as QuestionCreation, q.ViewCount,
           q.Score as QuestionScore, q.AnswerCount, q.FavoriteCount,
           a.Id as AnswerId, a.CreationDate as AnswerCreation, a.Score as AnswerScore,
           u.DisplayName as AnswerOwner
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on a.OwnerUserId = u.Id
    where q.PostTypeId = 1
),
RankedAnswers as (
    select qas.*,
           row_number() over (partition by qas.QuestionId order by qas.AnswerScore desc, qas.AnswerCreation asc) as AnswerRank,
           count(*) over (partition by qas.QuestionId) as AnswerCountPerQuestion,
           first_value(a.Body) over (partition by qas.QuestionId order by a.Score desc nulls last) as TopAnswerBody
    from QuestionAnswerStats qas
    left join Posts a on qas.AnswerId = a.Id
),
DuplicatesWithLinkInfo as (
    select pl.PostId as DuplicateId, pl.RelatedPostId as OriginalId,
           lt.Name as LinkTypeName,
           p1.Title as DuplicateTitle,
           p2.Title as OriginalTitle,
           u1.DisplayName as DuplicatePostOwner,
           u2.DisplayName as OriginalPostOwner
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    join Posts p1 on pl.PostId = p1.Id and p1.PostTypeId = 1
    join Posts p2 on pl.RelatedPostId = p2.Id and p2.PostTypeId = 1
    left join Users u1 on p1.OwnerUserId = u1.Id
    left join Users u2 on p2.OwnerUserId = u2.Id
    where lt.Name = 'Duplicate'
),
UserActivityWindow as (
    select u.Id as UserId, u.DisplayName,
           count(p.Id) filter (where p.PostTypeId = 1) as TotalQuestions,
           count(p.Id) filter (where p.PostTypeId = 2) as TotalAnswers,
           count(c.Id) as TotalComments,
           sum(vb.UpVotes) as TotalUpVotes,
           sum(vb.DownVotes) as TotalDownVotes,
           row_number() over (order by count(p.Id) desc nulls last) as ActivityRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join (
        select u.Id,
               coalesce(u.UpVotes,0) as UpVotes,
               coalesce(u.DownVotes,0) as DownVotes
        from Users u
    ) vb on vb.Id = u.Id
    group by u.Id, u.DisplayName
)
select distinct
    q.Id as QuestionID,
    q.Title,
    q.Tags,
    case when q.Score is null then 0 else q.Score end as QuestionScore,
    q.ViewCount,
    q.AnswerCount,
    q.FavoriteCount,
    lpe.LastEditDate,
    lpe.CloseReopenReason,
    bs.TotalBadges,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    bs.HasTagBadges,
    ra.AnswerId,
    ra.AnswerScore,
    ra.AnswerOwner,
    ra.AnswerRank,
    ra.AnswerCountPerQuestion,
    substr(nullif(ra.TopAnswerBody, ''), 1, 200) || coalesce(' ...', '') as TopAnswerBodySnippet,
    dwi.OriginalId as DuplicateOriginalID,
    dwi.OriginalTitle as DuplicateOfTitle,
    dwi.LinkTypeName,
    dwi.DuplicatePostOwner,
    dwi.OriginalPostOwner,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.TotalComments,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    ua.ActivityRank,
    concat_ws(' / ',
        coalesce(u.Location, 'Unknown Location'),
        coalesce(u.WebsiteUrl, 'No Website'),
        coalesce(u.AboutMe, 'No About Me Info')
    ) as UserMetaInfo,
    case
        when q.ClosedDate is null then 'Open'
        when q.ClosedDate is not null and q.LastActivityDate > q.ClosedDate then 'Reopened after closure'
        else 'Closed'
    end as OpenStatus,
    greatest(q.Score, coalesce(ra.AnswerScore,0)) * nullif(q.FavoriteCount, 0) + coalesce(bs.GoldBadges, 0) as SyntheticPopularityScore
from Posts q
left join LatestPostEdits lpe on q.Id = lpe.PostId
left join UserBadgesSummary bs on bs.UserId = q.OwnerUserId
left join RankedAnswers ra on q.Id = ra.QuestionId and ra.AnswerRank = 1
left join DuplicatesWithLinkInfo dwi on dwi.DuplicateId = q.Id
left join UserActivityWindow ua on ua.UserId = q.OwnerUserId
left join Users u on u.Id = q.OwnerUserId
where q.PostTypeId = 1
  and (
    -- complex predicate combining string functions and null logic on tags
    q.Tags is not null and
    (
        strpos(lower(q.Tags), '<sql>') > 0 or
        strpos(lower(q.Tags), '<performance>') > 0 or
        strpos(lower(q.Tags), '<indexes>') > 0 or
        strpos(lower(q.Tags), '<optimization>') > 0
    )
  )
  and (
    -- exclude questions with fewer than 5 views except if user rep is > 5000
    (q.ViewCount >= 5)
    or (select Reputation from Users where Id = q.OwnerUserId) > 5000
  )
order by SyntheticPopularityScore desc nulls last
limit 50;