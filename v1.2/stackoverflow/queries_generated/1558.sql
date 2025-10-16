-- {"query": "1558.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2305} 
with RecursiveUserActivity as (
    select
        U.Id as UserId,
        U.DisplayName,
        U.Reputation,
        count(distinct P.Id) filter (where P.PostTypeId = 1) as QuestionCount,
        count(distinct P_Answers.Id) as AnswerCount,
        sum(P.Score) filter (where P.PostTypeId = 1) as TotalQuestionScore,
        sum(P_Answers.Score) as TotalAnswerScore,
        row_number() over (order by U.Reputation desc, U.Id) as RankByReputation,
        bool_or(B.Class = 1) as HasGoldBadge,
        max(B.Date) filter (where B.Class = 3) as LastBronzeBadgeDate,
        min(P.CreationDate) as FirstPostDate,
        extract(epoch from max(P.LastActivityDate) - min(P.CreationDate))/86400.0 as ActivitySpanDays
    from Users U
    left join Posts P on P.OwnerUserId = U.Id
    left join Posts P_Answers on P_Answers.OwnerUserId = U.Id and P_Answers.PostTypeId = 2
    left join Badges B on B.UserId = U.Id
    group by U.Id, U.DisplayName, U.Reputation
),
TopTimedComments as (
    select
        C.PostId,
        P.OwnerUserId,
        C.UserId,
        C.CreationDate,
        lag(C.CreationDate) over (partition by C.PostId order by C.CreationDate) as PreviousCommentDate,
        extract(epoch from (C.CreationDate - lag(C.CreationDate) over (partition by C.PostId order by C.CreationDate))) as SecondsSincePrevComment,
        rank() over(partition by C.PostId order by extract(epoch from (C.CreationDate - lag(C.CreationDate) over (partition by C.PostId order by C.CreationDate)))) desc as TimeRankPerPost
    from Comments C
    inner join Posts P on P.Id = C.PostId
    where C.UserId is not null 
),
RelatedPostPairs as (
    select 
        PL.PostId,
        PL.RelatedPostId,
        L.Name as LinkType,
        RP1.PostTypeId as PostTypeFrom,
        RP2.PostTypeId as PostTypeTo
    from PostLinks PL
    join LinkTypes L on L.Id = PL.LinkTypeId
    join Posts RP1 on RP1.Id = PL.PostId
    join Posts RP2 on RP2.Id = PL.RelatedPostId
),
QuestionAnswerRatios as (
    select
        PA.OwnerUserId,
        sum(case when PP.PostTypeId = 1 then 1 else 0 end)::float as Questions,
        sum(case when PP.PostTypeId = 2 then 1 else 0 end)::float as Answers,
        case when sum(case when PP.PostTypeId = 1 then 1 else 0 end) > 0
            then sum(case when PP.PostTypeId = 2 then 1 else 0 end)::float / sum(case when PP.PostTypeId = 1 then 1 else 0 end)::float
            else null
        end as AnswerToQuestionRatio
    from Posts PA
    inner join Posts PP on (PP.Id = PA.Id or PP.Id = PA.ParentId) and PP.OwnerUserId = PA.OwnerUserId
    group by PA.OwnerUserId
),
TagPopularities as (
    select
        t.TagName,
        t.Count,
        (select coalesce(avg(P.Score),0)
         from Posts P 
         where P.PostTypeId = 1 and P.Tags ilike concat('%<', t.TagName, '>%')) as AverageScorePerTag,
        length(t.TagName),
        case when t.IsModeratorOnly = 1 then 'Advisor' else 'Participant' end as UserRoleMarker
    from Tags t
    where t.Count > 1000
    order by AverageScorePerTag desc, t.Count desc
),
UserBadgeWindows as (
    select
        B.UserId,
        B.Name,
        B.Class,
        B.Date,
        lag(B.Date) over (partition by B.UserId order by B.Date) as PreviousBadgeDate,
        lead(B.Date) over (partition by B.UserId order by B.Date) as NextBadgeDate,
        coalesce(
            extract(epoch from B.Date - lag(B.Date) over (partition by B.UserId order by B.Date)),
            -1
        ) as TimeSincePrevBadge,
        coalesce(
            extract(epoch from lead(B.Date) over (partition by B.UserId order by B.Date) - B.Date),
            -1
        ) as TimeToNextBadge
    from Badges B
),
PostHistoryEditGaps as (
    select
        PH.PostId,
        PH.PostHistoryTypeId,
        PH.CreationDate,
        lead(PH.CreationDate) over(partition by PH.PostId order by PH.CreationDate) - PH.CreationDate as NextEditGap,
        PH.UserId
    from PostHistory PH
    where PH.PostHistoryTypeId in (4,5,6,10,11)
),
PostsWithRevisionCount as (
    select
        PH.PostId,
        count(*) as RevisionCount
    from PostHistory PH
    group by PH.PostId
),
AggregatedPostRanks as (
    select
        P.Id,
        dense_rank() over (order by P.Score desc nulls last, P.ViewCount desc nulls last) as ScoreRank,
        dense_rank() over (order by coalesce(P.AnswerCount,0) desc) as AnswerCountRank,
        count(*) over (partition by P.OwnerUserId) as UserPostsTotal,
        max(CASE WHEN DATE_TRUNC('year', P.CreationDate) = DATE_TRUNC('year', current_date) THEN 1 ELSE 0 END) over (partition by P.OwnerUserId) as HasOutsideYearPost
    from Posts P
),
DetailedQuestions as (
    select 
        p.Id, p.Title, p.Tags, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount,
        ph.Id as LastPostHistoryId,
        rw.RevisionCount,
        P_H.Category as PostCategory,
        COALESCE(p.AnswerCount,0) as Answers,
        (select count(*) from Comments c where c.PostId = p.Id) as CommentTotal,
        case 
            when p.ClosedDate is null then 'Open' 
            else 'Closed' 
        end as CloseStatus,
        U.DisplayName, U.Reputation,
        concat_ws(' ', U.Location, U.WebsiteUrl) as LocationAndSite,
        (array_length(string_to_array(substring(p.Tags from '<([^>]+)>'), null,false))) as TagCount
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id
    left join PostsWithRevisionCount rw on rw.PostId = p.Id
    left join Users U on U.Id = p.OwnerUserId
    left join (
        select Id, 'Question'::varchar as Category from Posts where PostTypeId = 1
        union all 
        select Id, 'Answer' from Posts where PostTypeId = 2
    ) P_H on P_H.Id = p.Id
    where p.PostTypeId = 1
)
select
    RUA.UserId,
    RUA.DisplayName,
    RUA.Reputation,
    RUA.QuestionCount,
    RUA.AnswerCount,
    round(coalesce(RUA.TotalQuestionScore,0),2) as TotalQuestionScore,
    round(coalesce(RUA.TotalAnswerScore,0),2) as TotalAnswerScore,
    RUA.RankByReputation,
    coalesce(RUA.HasGoldBadge,false) as HasGoldBadge,
    RUA.LastBronzeBadgeDate,
    coalesce(round(RUA.ActivitySpanDays,2), 0) as ActivitySponsorSpanDays,
    avg(QAR.AnswerToQuestionRatio) filter (where QAR.AnswerToQuestionRatio is not null) over() as AvgAnswerToQuestionRatio,
    coalesce(tp.ScoreRank, -1) as RepresentativeTopScoreRank,
    coalesce(tc.TimeRankPerPost, 0) as MaxCommentInterarrivalTimeRank,
    tg.TagName,
    tg.Count as TagCountGlobal,
    round(tg.AverageScorePerTag, 2) as AvgTagScore,
    tg.UserRoleMarker,
    max(COALESCE(sub.BadgeGapsInDays, -1)) over (partition by RUA.UserId) as LongestBadgeGapDays,
    max(editGapGaps.seconds_between_edits) as MaxSecondsBetweenEdits
 
from RecursiveUserActivity RUA
left join QuestionAnswerRatios QAR on QAR.OwnerUserId = RUA.UserId
left join DetailedQuestions tp on tp.OwnerUserId = RUA.UserId
left join TopTimedComments tc on tc.UserId = RUA.UserId
left join TagPopularities tg on ' <' || tg.TagName || '> ' like '%<' || COALESCE((select unnest(string_to_array(DetailedQuestions.Tags, '><'))), '') || '>%'
left join (
    select
        UBW.UserId,
        max(case when UBW.TimeSincePrevBadge > 0 then UBW.TimeSincePrevBadge/86400.0 else null end) as BadgeGapsInDays
    from UserBadgeWindows UBW
    group by UBW.UserId
) sub on sub.UserId = RUA.UserId
left join (
    select ph.PostId, ph.UserId, extract(epoch from ph_next.CreationDate - ph.CreationDate) as seconds_between_edits
    from PostHistory ph
    join PostHistory ph_next on ph_next.PostId = ph.PostId and ph_next.CreationDate > ph.CreationDate
    where ph.UserId is not null and ph.PostHistoryTypeId in (4,5) and ph_next.PostHistoryTypeId in (4,5)
    order by ph.PostId, ph.CreationDate
) as editGapGaps on editGapGaps.UserId = RUA.UserId
where RUA.QuestionCount > 0 and RUA.AnswerCount > 0
group by
    RUA.UserId, RUA.DisplayName, RUA.Reputation, RUA.QuestionCount, RUA.AnswerCount,
    RUA.TotalQuestionScore, RUA.TotalAnswerScore, RUA.RankByReputation, RUA.HasGoldBadge,
    RUA.LastBronzeBadgeDate, RUA.ActivitySpanDays, tp.ScoreRank, tc.TimeRankPerPost, tg.TagName,
    tg.Count, tg.AverageScorePerTag, tg.UserRoleMarker, sub.BadgeGapsInDays
order by RUA.Reputation desc, RUA.UserId
limit 100;