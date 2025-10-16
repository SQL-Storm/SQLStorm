-- {"query": "929.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1099} 
with recursive UserBadgeRanks as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Class, b.Date) as BadgeRank
    from Users u
    join Badges b on b.UserId = u.Id
    where b.Date > '2020-01-01'
), RecentBadges as (
    select * from UserBadgeRanks where BadgeRank <= 3
), QuestionStats as (
    select
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        coalesce(p.AnswerCount,0) as AnswerCount,
        coalesce(p.FavoriteCount,0) as FavoriteCount,
        (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
        case 
            when p.ClosedDate is not null then 1
            else 0
        end as IsClosed,
        case
            when p.Tags is not null then array_to_string(array_agg(distinct unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><'))), ', ')
            else ''
        end as TagList
    from Posts p 
    where p.PostTypeId = 1
    group by p.Id
), AnswerRanks as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate,
        rank() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as ScoreRank
    from Posts a
    where a.PostTypeId = 2
), HighestAnswers as (
    select *
    from AnswerRanks
    where ScoreRank = 1
), UserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(distinct c.Id) as CommentsMade,
        max(p.CreationDate) as LastPostDate,
        greatest(u.LastAccessDate, max(p.LastActivityDate)) as LastActivity
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.LastAccessDate
), DuplicateLinks as (
    select pl.PostId as DuplicateQuestionId, pl.RelatedPostId as OriginalQuestionId
    from PostLinks pl
    where pl.LinkTypeId = 3
), ComplexUserPosts as (
    select 
        ua.UserId,
        ua.DisplayName,
        qs.QuestionId,
        qs.Title,
        qs.Score as QuestionScore,
        ha.AnswerId,
        ha.Score as TopAnswerScore,
        qb.BadgeName,
        qb.Class as BadgeClass,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        ua.CommentsMade,
        ua.LastActivity,
        dl.OriginalQuestionId,
        case when qs.IsClosed = 1 then 'Closed' else 'Open' end as QuestionStatus
    from UserActivity ua
    join QuestionStats qs on qs.OwnerUserId = ua.UserId
    left join HighestAnswers ha on ha.QuestionId = qs.QuestionId
    left join RecentBadges qb on qb.UserId = ua.UserId and qb.BadgeRank = 1
    left join DuplicateLinks dl on dl.DuplicateQuestionId = qs.QuestionId
    where ua.QuestionsPosted > 10 and qs.Score > 5 and (dl.OriginalQuestionId is null or dl.OriginalQuestionId <> qs.QuestionId)
)
select 
    cup.UserId,
    cup.DisplayName,
    cup.QuestionId,
    cup.Title,
    cup.QuestionScore,
    cup.AnswerId,
    cup.TopAnswerScore,
    cup.BadgeName,
    case cup.BadgeClass 
        when 1 then 'Gold' 
        when 2 then 'Silver' 
        when 3 then 'Bronze' 
        else 'Unknown' 
    end as BadgeClass,
    cup.QuestionsPosted,
    cup.AnswersPosted,
    cup.CommentsMade,
    cup.LastActivity,
    cup.OriginalQuestionId,
    cup.QuestionStatus,
    -- Complex expression: length of title * question score / (answers + 1) plus coalesce on badge class weighted score
    (char_length(cup.Title) * cup.QuestionScore / nullif(cup.AnswersPosted + 1,0))
    + coalesce(
        case cup.BadgeClass 
            when 1 then 10 
            when 2 then 5 
            when 3 then 2 
            else 0 
        end, 0) as CompositeScore
from ComplexUserPosts cup
where
    (cup.QuestionStatus = 'Open' or (cup.QuestionStatus = 'Closed' and cup.LastActivity > now() - interval '1 year'))
order by CompositeScore desc
limit 50;