-- {"query": "1120.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1472} 
with recursive UserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        coalesce((select max(ph.CreationDate) from PostHistory ph where ph.UserId = u.Id), u.LastAccessDate) as LastActive,
        (select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1) as QuestionsAsked,
        (select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 2) as AnswersGiven,
        (select count(*) from Comments c where c.UserId = u.Id) as CommentsMade,
        (select count(*) from Badges b where b.UserId = u.Id and b.Class = 1) as GoldBadges,
        (select count(*) from Badges b where b.UserId = u.Id and b.Class = 2) as SilverBadges,
        (select count(*) from Badges b where b.UserId = u.Id and b.Class = 3) as BronzeBadges
    from Users u
    where u.Reputation > 1000

    union all

    select 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.CreationDate,
        ua.LastActive,
        ua.QuestionsAsked,
        ua.AnswersGiven,
        ua.CommentsMade,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges
    from UserActivity ua
    where ua.QuestionsAsked > 0
), TopTags as (
    select
        t.TagName,
        t.Count,
        t.IsModeratorOnly,
        t.IsRequired,
        coalesce(p.Score,0) as LatestPostScore,
        p.Id as LatestPostId,
        p.CreationDate as LatestPostDate,
        p.OwnerUserId
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId
    where t.Count > 1000 and t.IsModeratorOnly = 0
), PostLinkDuplicates as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        lt.Name as LinkTypeName
    from PostLinks pl
    inner join LinkTypes lt on lt.Id = pl.LinkTypeId
    where pl.LinkTypeId = 3 -- duplicates only
), QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.AcceptedAnswerId,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerUserId,
        a.CreationDate as AnswerCreationDate,
        dense_rank() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
UserBadgesRanked as (
    select
        b.UserId,
        b.Name,
        b.Class,
        row_number() over (partition by b.UserId order by b.Class, b.Date desc) as BadgeRank
    from Badges b
    where b.Class in (1,2,3)
),
CloseReasonsCount as (
    select
        cht.Name as CloseReasonName,
        count(ph.Id) as CloseCount
    from PostHistory ph
    left join PostHistoryTypes cht on cht.Id = ph.PostHistoryTypeId
    where ph.PostHistoryTypeId = 10 -- Post Closed
    group by cht.Name
),
UserAggregates as (
    select
        u.Id,
        u.DisplayName,
        count(distinct p.Id) FILTER (WHERE p.PostTypeId = 1) as TotalQuestions,
        count(distinct p.Id) FILTER (WHERE p.PostTypeId = 2) as TotalAnswers,
        count(distinct c.Id) as TotalComments,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as TotalUpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as TotalDownVotes
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.PostId = p.Id
    group by u.Id, u.DisplayName
)
select distinct 
    ua.UserId, 
    ua.DisplayName,
    ua.Reputation,
    ua.LastActive,
    ua.QuestionsAsked,
    ua.AnswersGiven,
    ua.CommentsMade,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    tt.TagName,
    tt.Count as TagUses,
    tt.LatestPostId,
    tt.LatestPostScore,
    pl.RelatedPostId as DuplicateOfPost,
    qa.QuestionId,
    qa.Title as QuestionTitle,
    qa.AnswerId,
    qa.AnswerScore,
    ub.Name as BadgeName,
    ub.Class as BadgeClass,
    crc.CloseReasonName,
    crc.CloseCount,
    ua2.TotalQuestions,
    ua2.TotalAnswers,
    ua2.TotalComments,
    ua2.TotalUpVotes,
    ua2.TotalDownVotes,
    length(coalesce(u.AboutMe, '')) as AboutMeLength,
    case 
        when ua.GoldBadges > 0 then 'Veteran'
        when ua.SilverBadges > 5 then 'Experienced'
        else 'Newbie' 
    end as UserLevel,
    substring(u.DisplayName from '^(\\w+)') as FirstNameFragment
from UserActivity ua
left join TopTags tt on tt.OwnerUserId = ua.UserId
left join PostLinkDuplicates pl on pl.PostId = tt.LatestPostId
left join QuestionAnswerStats qa on qa.AnswerOwnerUserId = ua.UserId and qa.AnswerRank = 1
left join UserBadgesRanked ub on ub.UserId = ua.UserId and ub.BadgeRank = 1
left join CloseReasonsCount crc on crc.CloseReasonName ilike any (array[
    '%duplicate%',
    '%off-topic%',
    '%clarity%',
    '%focus%',
    '%opinion%'
])
left join Users u on u.Id = ua.UserId
left join UserAggregates ua2 on ua2.Id = ua.UserId
where ua.Reputation > 2000
and (qa.QuestionDate > current_date - interval '365 days' or qa.QuestionDate is null)
and (
    (tt.IsRequired = 0 and tt.Count > 2000)
    or tt.TagName is null
)
order by ua.Reputation desc, ua.UserId, tt.TagName, qa.QuestionDate desc
limit 100;