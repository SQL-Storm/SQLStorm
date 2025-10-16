-- {"query": "1268.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1693} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        coalesce(sum(v.VoteCount),0) as TotalVotesReceived,
        row_number() over (partition by u.Location order by coalesce(sum(v.VoteCount),0) desc nulls last) as UserRankByVotes,
        dense_rank() over (order by u.Reputation desc) as ReputationRank
    from
        Users u
        left join Posts p on p.OwnerUserId = u.Id
        left join (
            select
                PostId,
                count(*) as VoteCount
            from 
                Votes
            where 
                VoteTypeId in (2,3) /* UpMod, DownMod */
            group by PostId
        ) v on v.PostId = p.Id
        left join Comments c on c.UserId = u.Id
    where u.Reputation > 100
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location
),
UserBadgeStats as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        max(b.Date) filter (where b.Class = 1) as LastGoldBadgeDate
    from Badges b
    group by b.UserId
),
UserActivityWithBadges as (
    select
        r.*,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.LastGoldBadgeDate
    from RecursiveUserActivity r
    left join UserBadgeStats ub on ub.UserId = r.UserId
),
PostsWithTagsExpanded as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        trim(tag) as Tag,
        row_number() over (partition by p.Id order by p.CreationDate desc) as rn
    from 
        Posts p,
        unnest(string_to_array(replace(replace(p.Tags, '<', ''), '>', ' '))) as tag
    where p.Tags is not null
        and p.PostTypeId = 1
), 
TopTagsByScore as (
    select
        pe.Tag,
        count(*) as QuestionCount,
        avg(pe.Score) as AvgScore,
        sum(pe.ViewCount) as TotalViews
    from 
        PostsWithTagsExpanded pe
    group by pe.Tag
    having count(*) > 10
),
PostWithAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        coalesce(a.AnswerCount, 0) as NumAnswers,
        coalesce(a.AvgAnswerScore, 0) as AvgAnswerScore,
        q.OwnerUserId,
        q.Tags
    from
        Posts q
        left join (
            select 
                ParentId, 
                count(*) as AnswerCount, 
                avg(Score) as AvgAnswerScore
            from Posts
            where PostTypeId = 2
            group by ParentId
        ) a on a.ParentId = q.Id
    where q.PostTypeId = 1
),
RankedAnswers as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId as AnswerOwnerId,
        a.Score,
        a.CreationDate,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as RankByScore
    from Posts a
    where a.PostTypeId = 2
),
AnswerVotesInfo as (
    select
        a.AnswerId,
        a.QuestionId,
        a.AnswerOwnerId,
        a.Score,
        vup.UpVotes,
        vdown.DownVotes,
        (vup.UpVotes - vdown.DownVotes) as NetVotes
    from RankedAnswers a
    left join (
        select
            v.PostId,
            count(*) as UpVotes
        from Votes v
        where VoteTypeId = 2
        group by v.PostId
    ) vup on vup.PostId = a.AnswerId
    left join (
        select
            v.PostId,
            count(*) as DownVotes
        from Votes v
        where VoteTypeId = 3
        group by v.PostId
    ) vdown on vdown.PostId = a.AnswerId
    where a.RankByScore <= 3
),
TopUsers by Tags as (
    select
        t.Tag,
        u.UserId,
        u.DisplayName,
        ua.AnswerScoreAvg,
        ua.QuestionScoreAvg
    from (
        select 
            p.OwnerUserId as UserId,
            trim(tag) as Tag,
            avg(case when p.PostTypeId = 1 then p.Score else null end) as QuestionScoreAvg,
            avg(case when p.PostTypeId = 2 then p.Score else null end) as AnswerScoreAvg
        from Posts p
        cross join lateral unnest(string_to_array(replace(replace(p.Tags, '<', ''), '>', ' '))) tag
        group by p.OwnerUserId, trim(tag)
    ) ua
    join Tags t on t.TagName = ua.Tag
    join Users u on u.Id = ua.UserId
    where ua.QuestionScoreAvg is not null or ua.AnswerScoreAvg is not null
),
FilteredCloseVotes as (
    select
        ph.PostId,
        count(distinct ph.UserId) as CloseVoteCount,
        max(ph.CreationDate) as LastCloseVoteDate
    from PostHistory ph
    where ph.PostHistoryTypeId = 10 -- Post Closed
    group by ph.PostId
)
select
    u.UserId,
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.QuestionCount,
    u.AnswerCount,
    u.CommentCount,
    u.TotalVotesReceived,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    coalesce(qa.NumAnswers,0) as TotalQuestionsWithAnswers,
    coalesce(qa.AvgAnswerScore,0) as AvgAnswerScorePerQuestion,
    t.Tag as PopularTag,
    t.QuestionCount as TagQuestionCount,
    t.AvgScore as TagAvgQuestionScore,
    t.TotalViews as TagTotalViews,
    acv.CloseVoteCount as QuestionCloseVotes,
    case when acv.CloseVoteCount > 0 then True else False end as HasCloseVotes,
    (select avg(AnswerScore) from AnswerVotesInfo avi
     where avi.AnswerOwnerId = u.UserId
     and avi.NetVotes > 0) as AvgPositiveNetVotesOnAnswers,
    rank() over (order by u.Reputation desc) as OverallUserRank
from UserActivityWithBadges u
left join PostWithAnswerStats qa on qa.OwnerUserId = u.UserId
left join TopTagsByScore t on strpos(coalesce(qa.Tags,''), t.Tag) > 0
left join FilteredCloseVotes acv on acv.PostId = qa.QuestionId
where u.GoldBadges >= 1 and u.Reputation > 10000
order by u.Reputation desc, PopularTag asc
limit 100;