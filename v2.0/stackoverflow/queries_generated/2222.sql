-- {"query": "2222.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1628} 
with RecursiveTagHierarchy as (
    select t.Id, t.TagName, t.Count, 1 as Level, t.WikiPostId
    from Tags t
    where t.Count > 5000
    union all
    select t2.Id, t2.TagName, t2.Count, r.Level + 1, t2.WikiPostId
    from Tags t2
    join RecursiveTagHierarchy r on t2.WikiPostId = r.WikiPostId and r.Level < 3
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        coalesce(sum(case when b.TagBased = 1 then 1 else 0 end), 0) as TagBasedBadges,
        row_number() over (partition by u.Id order by b.Date desc) as RecentBadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName
),
UserReputationWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        avg(u.Reputation) over (order by u.CreationDate rows between 10 preceding and current row) as AvgReputationPast11Users,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as TotalUpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as TotalDownVotes
    from Users u
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        count(a.Id) as AnswerCount,
        coalesce(max(a.Score), 0) as MaxAnswerScore,
        (select count(*) from Comments c where c.PostId = q.Id) as CommentCountOnQuestion,
        (select count(*) from Comments c where c.PostId in (select Id from Posts where ParentId = q.Id)) as CommentCountOnAnswers,
        q.FavoriteCount,
        case 
            when q.ClosedDate is not null then 1
            else 0
        end as IsClosed,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation,
        string_agg(distinct ltp.Name, ',' order by ltp.Name) as LinkTypesToRelated,
        coalesce(plcnt.DuplicateCount,0) as DuplicateLinkCount
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = q.OwnerUserId
    left join (
        select pl.PostId, count(*) as DuplicateCount
        from PostLinks pl
        where pl.LinkTypeId = 3 -- Duplicate
        group by pl.PostId
    ) plcnt on plcnt.PostId = q.Id
    left join PostLinks pl on pl.PostId = q.Id
    left join LinkTypes ltp on ltp.Id = pl.LinkTypeId
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.Tags, q.CreationDate, q.Score, q.FavoriteCount, q.ClosedDate, u.DisplayName, u.Reputation, plcnt.DuplicateCount
),
TagNameCounts as (
    select
        th.TagName,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionsWithTag,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswersWithTag,
        avg(p.Score) filter (where p.PostTypeId = 1) as AvgQuestionScore,
        avg(p.Score) filter (where p.PostTypeId = 2) as AvgAnswerScore
    from RecursiveTagHierarchy th
    left join Posts p on p.Tags is not null and position('<' || th.TagName || '>' in p.Tags) > 0
    group by th.TagName
),
FinalUserStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        urs.AvgReputationPast11Users,
        userbadges.GoldBadges,
        userbadges.SilverBadges,
        userbadges.BronzeBadges,
        userbadges.TagBasedBadges,
        urs.TotalUpVotes,
        urs.TotalDownVotes,
        case when u.Views > 0 then round(1.0 * u.UpVotes / u.Views, 4) else null end as UpVotesPerViewRatio,
        case when u.DownVotes > 0 then round(1.0 * u.DownVotes / u.Views, 4) else null end as DownVotesPerViewRatio,
        u.Location,
        length(u.AboutMe) as AboutMeLength,
        dense_rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join UserReputationWindow urs on u.Id = urs.Id
    left join UserBadgeStats userbadges on u.Id = userbadges.UserId
)
select 
    fas.ReputationRank,
    fas.DisplayName,
    fas.Location,
    coalesce(fas.AboutMeLength, 0) as AboutMeLength,
    fas.Reputation,
    fas.AvgReputationPast11Users,
    fas.GoldBadges,
    fas.SilverBadges,
    fas.BronzeBadges,
    fas.TagBasedBadges,
    fas.TotalUpVotes,
    fas.TotalDownVotes,
    fas.UpVotesPerViewRatio,
    fas.DownVotesPerViewRatio,
    qas.Title as TopQuestionTitle,
    qas.AnswerCount,
    qas.MaxAnswerScore,
    qas.CommentCountOnQuestion,
    qas.CommentCountOnAnswers,
    qas.FavoriteCount,
    case when qas.IsClosed = 1 then 'Closed' else 'Open' end as QuestionStatus,
    qas.LinkTypesToRelated,
    qas.DuplicateLinkCount,
    tnc.QuestionsWithTag,
    tnc.AnswersWithTag,
    tnc.AvgQuestionScore,
    tnc.AvgAnswerScore
from FinalUserStats fas
left join Lateral (
    select qas_sub.Title, qas_sub.AnswerCount, qas_sub.MaxAnswerScore, qas_sub.CommentCountOnQuestion, qas_sub.CommentCountOnAnswers, qas_sub.FavoriteCount, qas_sub.IsClosed, qas_sub.LinkTypesToRelated, qas_sub.DuplicateLinkCount
    from QuestionAnswerStats qas_sub
    join Posts p2 on p2.OwnerUserId = fas.UserId and p2.Id = qas_sub.QuestionId
    order by qas_sub.Score desc nulls last
    limit 1
) qas on true
left join Lateral (
    select tnc_sub.*
    from TagNameCounts tnc_sub
    join Posts p3 on p3.OwnerUserId = fas.UserId and p3.PostTypeId = 1 and position('<' || tnc_sub.TagName || '>' in p3.Tags) > 0
    order by tnc_sub.QuestionsWithTag desc nulls last
    limit 1
) tnc on true
where fas.ReputationRank <= 100
order by fas.ReputationRank;