-- {"query": "2987.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2119}
with UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        row_number() over (partition by u.Id order by max(b.Date) desc nulls last) as BadgeRank
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
), LatestBestAnswer as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score,
        a.CreationDate,
        a.OwnerUserId,
        rank() over (partition by a.ParentId order by a.Score desc, a.CreationDate) as AnswerRank
    from Posts a
    where a.PostTypeId = 2
), QuestionWithAcceptedAndTopAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate as QuestionCreation,
        acc.Id as AcceptedAnswerId,
        acc.Score as AcceptedAnswerScore,
        topa.AnswerId as TopAnswerId,
        topa.Score as TopAnswerScore,
        q.Tags,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        q.LastActivityDate
    from Posts q
    left join Posts acc on acc.Id = q.AcceptedAnswerId and acc.PostTypeId = 2
    left join LatestBestAnswer topa on topa.QuestionId = q.Id and topa.AnswerRank = 1
    where q.PostTypeId = 1
), TagQuestions as (
    select
        qt.QuestionId,
        unnest(string_to_array(substring(q.Tags, 2, char_length(q.Tags)-2), '><')) as TagName
    from QuestionWithAcceptedAndTopAnswers qt
    join Posts q on q.Id = qt.QuestionId
    where q.Tags is not null
), TagAggregates as (
    select
        tq.TagName,
        count(distinct tq.QuestionId) as QuestionCount,
        avg(q.ViewCount) as AvgViews,
        sum(q.FavoriteCount) as TotalFavorites,
        avg(coalesce(q.AcceptedAnswerScore, 0)) as AvgAcceptedAnswerScore,
        avg(coalesce(q.TopAnswerScore, 0)) as AvgTopAnswerScore
    from TagQuestions tq
    join QuestionWithAcceptedAndTopAnswers q on q.QuestionId = tq.QuestionId
    group by tq.TagName
), QuestionCloseHistory as (
    select
        ph.PostId,
        ph.CreationDate,
        crt.Name as CloseReason,
        row_number() over (partition by ph.PostId order by ph.CreationDate desc) as CloseRank
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId and pht.Name = 'Post Closed'
    left join CloseReasonTypes crt on cast(crt.Id as varchar) = ph.Comment
), LatestCloseInfo as (
    select
        PostId,
        CloseReason,
        CreationDate
    from QuestionCloseHistory
    where CloseRank = 1
), QuestionsWithCloseInfo as (
    select
        q.QuestionId,
        q.Title,
        q.QuestionCreation as CreationDate,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        lci.CloseReason,
        lci.CreationDate as CloseDate
    from QuestionWithAcceptedAndTopAnswers q
    left join LatestCloseInfo lci on lci.PostId = q.QuestionId
), UserActivityWindows as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        count(p.Id) filter (where p.PostTypeId = 1) over (partition by u.Id order by u.CreationDate rows between unbounded preceding and current row) as QuestionsCreated,
        count(p.Id) filter (where p.PostTypeId = 2) over (partition by u.Id order by u.CreationDate rows between unbounded preceding and current row) as AnswersCreated,
        count(b.Id) over (partition by u.Id order by u.CreationDate rows between unbounded preceding and current row) as BadgesEarned,
        sum(v.SumUpVotes) over (partition by u.Id order by u.CreationDate rows between unbounded preceding and current row) as TotalUpVotes,
        sum(v.SumDownVotes) over (partition by u.Id order by u.CreationDate rows between unbounded preceding and current row) as TotalDownVotes
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join (
        select
            p.OwnerUserId,
            sum(case when v.VoteTypeId = 2 then 1 else 0 end) as SumUpVotes,
            sum(case when v.VoteTypeId = 3 then 1 else 0 end) as SumDownVotes
        from Votes v
        join Posts p on p.Id = v.PostId
        group by p.OwnerUserId
    ) v on v.OwnerUserId = u.Id
), UserTopTags as (
    select
        u.Id as UserId,
        tag.TagName,
        count(*) as QuestionsInTag,
        rank() over (partition by u.Id order by count(*) desc) as TagRank
    from Users u
    join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
    join TagQuestions tag on tag.QuestionId = p.Id
    group by u.Id, tag.TagName
), UserTopTagAggregates as (
    select
        ut.UserId,
        ut.TagName,
        ut.QuestionsInTag,
        ta.QuestionCount,
        ta.AvgViews,
        ta.TotalFavorites,
        ta.AvgAcceptedAnswerScore,
        ta.AvgTopAnswerScore
    from UserTopTags ut
    join TagAggregates ta on ta.TagName = ut.TagName
    where ut.TagRank <= 3
), PostsWithVotesCte as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.Score,
        coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end),0) as UpVotes,
        coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end),0) as DownVotes,
        p.CreationDate,
        p.Tags,
        p.AcceptedAnswerId,
        p.ParentId,
        p.ViewCount
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.PostTypeId, p.OwnerUserId, p.Title, p.Score, p.CreationDate, p.Tags, p.AcceptedAnswerId, p.ParentId, p.ViewCount
), HighImpactPosts as (
    select
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.UpVotes,
        p.DownVotes,
        u.DisplayName as OwnerName,
        case
            when p.PostTypeId = 1 then 'Question'
            when p.PostTypeId = 2 then 'Answer'
            else 'Other'
        end as PostType,
        case 
            when p.AcceptedAnswerId is not null then 1
            else 0
        end as HasAcceptedAnswer,
        p.CreationDate,
        round(
            (
                p.UpVotes * 3.0 - p.DownVotes * 2.0 + ln(nullif(p.ViewCount,0) + 1) * 1.5 + greatest(p.Score,0) * 2.0
            ), 2
        ) as WeightedScore,
        p.OwnerUserId
    from PostsWithVotesCte p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId in (1,2) and (p.Score > 10 or p.ViewCount > 1000)
)
select
    hip.Id,
    hip.Title,
    hip.PostType,
    hip.Score,
    hip.ViewCount,
    hip.UpVotes,
    hip.DownVotes,
    hip.WeightedScore,
    coalesce(bc.GoldBadges,0) as OwnerGoldBadges,
    coalesce(bc.SilverBadges,0) as OwnerSilverBadges,
    coalesce(bc.BronzeBadges,0) as OwnerBronzeBadges,
    coalesce(tq.TagName, 'NoTag') as TopTag,
    ta.QuestionCount as TagQuestionsCount,
    ta.AvgViews as TagAvgViews,
    ta.TotalFavorites as TagTotalFavorites,
    ta.AvgAcceptedAnswerScore as TagAvgAcceptedAnswerScore,
    ta.AvgTopAnswerScore as TagAvgTopAnswerScore,
    qc.CloseReason,
    qc.CloseDate,
    row_number() over (partition by hip.PostType order by hip.WeightedScore desc) as RankWithinType
from HighImpactPosts hip
left join UserBadgeCounts bc on bc.UserId = hip.OwnerUserId and bc.BadgeRank = 1
left join lateral (
    select ut.TagName
    from UserTopTagAggregates ut
    where ut.UserId = hip.OwnerUserId
    order by ut.QuestionsInTag desc limit 1
) tq on true
left join TagAggregates ta on ta.TagName = tq.TagName
left join QuestionsWithCloseInfo qc on qc.QuestionId = hip.Id and hip.PostType = 'Question'
where hip.Score is not null
order by hip.PostType, RankWithinType
limit 100;