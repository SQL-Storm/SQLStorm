-- {"query": "710.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1800} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(distinct c.Id) as CommentsMade,
        coalesce(sum(v.VoteTypeId = 2)::int, 0) as UpVotesReceived,
        coalesce(sum(v.VoteTypeId = 3)::int, 0) as DownVotesReceived,
        row_number() over (partition by u.Id order by ph.CreationDate desc) as LastPostHistoryRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.PostId = p.Id
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
UserBadgeCounts as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerUserId,
        a.CreationDate as AnswerCreationDate,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
TagPopularity as (
    select
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as Tag,
        count(*) as TagCount,
        avg(p.Score) as AvgScore,
        max(p.ViewCount) as MaxViewCount
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
    group by Tag
    having count(*) > 100
),
TopTagsWithGoldBadges as (
    select
        tp.Tag,
        tp.TagCount,
        tp.AvgScore,
        ub.GoldBadges,
        row_number() over (order by tp.TagCount desc, tp.AvgScore desc) as TagRank
    from TagPopularity tp
    left join (
        select ubt.UserId, count(*) as GoldBadges
        from Badges ubt
        join Posts up on up.OwnerUserId = ubt.UserId
        where ubt.Class = 1
        group by ubt.UserId
    ) ub on ub.UserId in (
        select distinct p.OwnerUserId from Posts p 
        where p.PostTypeId = 1 and p.Tags like concat('%<', tp.Tag, '>%')
    )
    where tp.TagCount > 500
),
DuplicateQuestions as (
    select
        pl.PostId as DuplicateQuestionId,
        pl.RelatedPostId as OriginalQuestionId,
        pq.Title as DuplicateTitle,
        po.Title as OriginalTitle,
        pl.CreationDate as LinkDate
    from PostLinks pl
    join Posts pq on pq.Id = pl.PostId and pq.PostTypeId = 1
    join Posts po on po.Id = pl.RelatedPostId and po.PostTypeId = 1
    where pl.LinkTypeId = 3
),
UserActivityRanked as (
    select
        rua.*,
        coalesce(ubc.GoldBadges,0) as GoldBadges,
        coalesce(ubc.SilverBadges,0) as SilverBadges,
        coalesce(ubc.BronzeBadges,0) as BronzeBadges,
        coalesce(ubc.TotalBadges,0) as TotalBadges,
        rank() over (order by rua.Reputation desc, rua.QuestionsPosted desc, rua.AnswersPosted desc) as UserRank
    from RecursiveUserActivity rua
    left join UserBadgeCounts ubc on ubc.UserId = rua.UserId
),
FilteredAnswers as (
    select
        qa.QuestionId,
        qa.Title,
        qa.OwnerUserId as QuestionOwner,
        qa.QuestionScore,
        qa.ViewCount,
        qa.AnswerId,
        qa.AnswerScore,
        qa.AnswerOwnerUserId,
        qa.AnswerCreationDate,
        qa.AnswerRank,
        ua.Reputation as AnswerOwnerReputation,
        ua.TotalBadges as AnswerOwnerBadges
    from QuestionAnswerStats qa
    left join UserActivityRanked ua on ua.UserId = qa.AnswerOwnerUserId
    where qa.AnswerScore > 0 and qa.AnswerRank <= 3
),
TopUsersWithAnswers as (
    select
        f.AnswerOwnerUserId,
        u.DisplayName,
        count(*) as NumTopAnswers,
        avg(f.AnswerScore) as AvgAnswerScore,
        max(f.AnswerScore) as MaxAnswerScore,
        sum(f.AnswerScore) as TotalAnswerScore,
        max(f.QuestionScore) as MaxQuestionScoreAnswered
    from FilteredAnswers f
    join Users u on u.Id = f.AnswerOwnerUserId
    group by f.AnswerOwnerUserId, u.DisplayName
    having count(*) >= 5
),
FinalQuestionMetrics as (
    select
        q.Id,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.Tags,
        coalesce(ta.NumTopAnswers, 0) as TopAnswerCount,
        coalesce(ta.AvgAnswerScore, 0) as AvgTopAnswerScore,
        coalesce(ta.TotalAnswerScore, 0) as TotalTopAnswerScore,
        coalesce(dq.DuplicateQuestionId, null) as IsDuplicate,
        case when q.ClosedDate is not null then 1 else 0 end as IsClosed,
        row_number() over (partition by q.Tags order by q.ViewCount desc) as RankByTagViewCount
    from Posts q
    left join TopUsersWithAnswers ta on q.OwnerUserId = ta.AnswerOwnerUserId
    left join DuplicateQuestions dq on dq.DuplicateQuestionId = q.Id
    where q.PostTypeId = 1
)
select 
    fqm.Id as QuestionId,
    fqm.Title,
    fqm.CreationDate,
    fqm.Score,
    fqm.ViewCount,
    fqm.Tags,
    fqm.TopAnswerCount,
    fqm.AvgTopAnswerScore,
    fqm.TotalTopAnswerScore,
    fqm.IsDuplicate,
    fqm.IsClosed,
    fqm.RankByTagViewCount,
    uar.DisplayName as QuestionOwnerName,
    uar.Reputation as QuestionOwnerReputation,
    uar.GoldBadges as QuestionOwnerGoldBadges,
    uar.SilverBadges as QuestionOwnerSilverBadges,
    uar.BronzeBadges as QuestionOwnerBronzeBadges,
    (
        select string_agg(distinct pt.Name, ',' order by pt.Name)
        from PostTypes pt
        where pt.Id in (
            select distinct p.PostTypeId
            from Posts p
            where p.OwnerUserId = fqm.Id
            limit 5
        )
    ) as OwnerPostTypesSample,
    case
        when fqm.IsClosed = 1 then 'Closed'
        when fqm.IsDuplicate is not null then 'Duplicate'
        else 'Open'
    end as PostStatus,
    substring(fqm.Tags from 2 for char_length(fqm.Tags)-2) as TagsExtracted
from FinalQuestionMetrics fqm
left join UserActivityRanked uar on uar.UserId = fqm.Id
where fqm.ViewCount > 1000
order by fqm.ViewCount desc, fqm.Score desc
limit 100;