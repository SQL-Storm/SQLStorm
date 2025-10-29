-- {"query": "2548.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1637}
with RecursiveTags as (
    select
        p.Id as PostId,
        trim(substring(tg from 1 for char_length(tg))) as Tag
    from
        Posts p
        join (
            -- split tags like '<tag1><tag2>' into rows: dialect-agnostic simulation using recursive CTE
            with recursive splitter(post_id, tags, tag, rest) as (
                select p0.Id, p0.Tags, null::varchar, p0.Tags from Posts p0 where p0.Tags is not null
                union all
                select
                    post_id,
                    rest,
                    case
                        when position('><' in rest) = 0 then
                            case
                                when left(rest,1) = '<' and right(rest,1) = '>' then substring(rest from 2 for char_length(rest)-2)
                                else rest
                            end
                        else
                            case
                                when left(rest,1) = '<' then substring(rest from 2 for position('><' in rest)-1)
                                else substring(rest from 1 for position('><' in rest)-1)
                            end
                    end,
                    case
                        when position('><' in rest) = 0 then ''
                        else substring(rest from position('><' in rest)+2)
                    end
                from splitter
                where rest <> ''
            )
            select post_id as Id, tag as tg from splitter where tag is not null and tag <> ''
        ) s on s.Id = p.Id
    where p.Tags is not null
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationRank as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        dense_rank() over (order by u.Reputation desc) as ReputationRank,
        coalesce(ubc_g.GoldCount,0) as GoldBadges,
        coalesce(ubc_s.SilverCount,0) as SilverBadges,
        coalesce(ubc_b.BronzeCount,0) as BronzeBadges
    from Users u
    left join (
        select UserId, BadgeCount as GoldCount from UserBadgeCounts where Class = 1
    ) ubc_g on u.Id = ubc_g.UserId
    left join (
        select UserId, BadgeCount as SilverCount from UserBadgeCounts where Class = 2
    ) ubc_s on u.Id = ubc_s.UserId
    left join (
        select UserId, BadgeCount as BronzeCount from UserBadgeCounts where Class = 3
    ) ubc_b on u.Id = ubc_b.UserId
),
PostAnswers as (
    select
        p.Id,
        p.ParentId,
        p.Score,
        p.CreationDate,
        p.OwnerUserId
    from Posts p
    where p.PostTypeId = 2
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        count(a.Id) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        min(a.Score) as MinAnswerScore,
        max(a.CreationDate) as LastAnswerDate
    from Posts q
    left join PostAnswers a on a.ParentId = q.Id
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.OwnerUserId
),
QuestionCloseInfo as (
    select
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate else null end) as CloseDate,
        max(case when ph.PostHistoryTypeId = 10 then ph.Comment else null end) as CloseReasonId
    from PostHistory ph
    where ph.PostHistoryTypeId = 10
    group by ph.PostId
),
QuestionTagAgg as (
    select
        rt.PostId,
        string_agg(rt.Tag, ', ') as TagsList,
        count(*) as TagCount
    from RecursiveTags rt
    group by rt.PostId
),
TopQuestions as (
    select
        qas.QuestionId,
        qas.Title,
        qas.AnswerCount,
        qas.AvgAnswerScore,
        qas.MaxAnswerScore,
        qas.MinAnswerScore,
        qas.LastAnswerDate,
        qc.CloseDate,
        qc.CloseReasonId,
        qta.TagsList,
        qta.TagCount,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation
    from QuestionAnswerStats qas
    left join QuestionCloseInfo qc on qas.QuestionId = qc.PostId
    left join QuestionTagAgg qta on qas.QuestionId = qta.PostId
    left join Users u on qas.OwnerUserId = u.Id
    where qas.AnswerCount > 0
),
FilteredVotes as (
    select
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as Favorites
    from Votes v
    join VoteTypes vt on v.VoteTypeId = vt.Id
    group by v.PostId
),
AnswerWithVotes as (
    select
        pa.Id as AnswerId,
        pa.ParentId as QuestionId,
        pa.Score,
        coalesce(fv.UpVotes,0) as UpVotes,
        coalesce(fv.DownVotes,0) as DownVotes,
        coalesce(fv.Favorites,0) as Favorites
    from PostAnswers pa
    left join FilteredVotes fv on pa.Id = fv.PostId
),
AnswerRankings as (
    select
        awv.AnswerId,
        awv.QuestionId,
        awv.Score,
        awv.UpVotes,
        awv.DownVotes,
        awv.Favorites,
        rank() over (partition by awv.QuestionId order by awv.UpVotes desc, awv.Score desc) as UpVoteRank
    from AnswerWithVotes awv
),
TopAnswersPerQuestion as (
    select
        ar.QuestionId,
        ar.AnswerId,
        ar.Score,
        ar.UpVotes,
        ar.DownVotes,
        ar.Favorites
    from AnswerRankings ar
    where ar.UpVoteRank <= 3
),
FinalReport as (
    select
        tq.QuestionId,
        tq.Title,
        tq.OwnerName,
        tq.OwnerReputation,
        tq.AnswerCount,
        coalesce(tq.AvgAnswerScore,0) as AvgAnswerScore,
        coalesce(tq.MaxAnswerScore,0) as MaxAnswerScore,
        coalesce(tq.MinAnswerScore,0) as MinAnswerScore,
        tq.LastAnswerDate,
        tq.CloseDate,
        crt.Name as CloseReason,
        tq.TagsList,
        tq.TagCount,
        count(ta.AnswerId) as TopAnswerCount,
        coalesce(sum(ta.UpVotes),0) as SumTopAnswerUpVotes,
        coalesce(sum(ta.Favorites),0) as SumTopAnswerFavorites,
        case
          when tq.CloseDate is not null then 'Closed'
          else 'Open'
        end as PostStatus
    from TopQuestions tq
    left join CloseReasonTypes crt on crt.Id = CAST(tq.CloseReasonId AS integer)
    left join TopAnswersPerQuestion ta on tq.QuestionId = ta.QuestionId
    group by
        tq.QuestionId, tq.Title, tq.OwnerName, tq.OwnerReputation, tq.AnswerCount,
        tq.AvgAnswerScore, tq.MaxAnswerScore, tq.MinAnswerScore, tq.LastAnswerDate,
        tq.CloseDate, crt.Name, tq.TagsList, tq.TagCount
)
select
    fr.QuestionId,
    fr.Title,
    fr.OwnerName,
    fr.OwnerReputation,
    fr.AnswerCount,
    fr.AvgAnswerScore,
    fr.MaxAnswerScore,
    fr.MinAnswerScore,
    fr.LastAnswerDate,
    fr.CloseDate,
    fr.CloseReason,
    fr.TagsList,
    fr.TagCount,
    fr.TopAnswerCount,
    fr.SumTopAnswerUpVotes,
    fr.SumTopAnswerFavorites,
    fr.PostStatus,
    case
      when fr.OwnerReputation > 100000 then 'Legendary'
      when fr.OwnerReputation between 10000 and 100000 then 'Expert'
      when fr.OwnerReputation between 1000 and 9999 then 'Intermediate'
      else 'Novice'
    end as OwnerReputationCategory,
    substring(fr.Title from 1 for 30) || '...' as ShortTitleSnippet
from FinalReport fr
where fr.TagCount >= 3
order by
    fr.OwnerReputation desc,
    fr.SumTopAnswerUpVotes desc,
    fr.AnswerCount desc
limit 100;