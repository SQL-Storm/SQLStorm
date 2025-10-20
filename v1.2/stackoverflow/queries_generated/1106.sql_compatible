with recursive UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
QuestionStats as (
    select
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        coalesce(p.AnswerCount,0) as AnswerCount,
        p.FavoriteCount,
        p.Tags,
        array_length(string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags) - 2), '><'),1) as TagCount
    from Posts p
    where p.PostTypeId = 1
),
LatestAnswerScores as (
    select
        a.ParentId as QuestionId,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        count(*) as TotalAnswers
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
),
TopVoters as (
    select
        v.PostId,
        count(*) as VoteCount,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
),
PostActivityChanges as (
    select
        ph.PostId,
        max(ph.CreationDate) as LastActivityChange,
        count(*) as EditCount,
        bool_or(ph.PostHistoryTypeId in (10,11,12,13)) as HasClosureOrDeletion,
        string_agg(distinct pht.Name, ',') as HistoryTypesInvolved
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
    group by ph.PostId
),
QuestionWithActivities as (
    select
        q.QuestionId,
        q.Title,
        q.OwnerUserId,
        q.Score,
        q.ViewCount,
        q.CreationDate,
        q.AnswerCount,
        q.FavoriteCount,
        q.Tags,
        q.TagCount,
        la.AvgAnswerScore,
        la.MaxAnswerScore,
        coalesce(tv.VoteCount, 0) as TotalVotes,
        coalesce(tv.UpVotes, 0) as UpVotes,
        coalesce(tv.DownVotes, 0) as DownVotes,
        pac.LastActivityChange,
        pac.EditCount,
        pac.HasClosureOrDeletion,
        pac.HistoryTypesInvolved
    from QuestionStats q
    left join LatestAnswerScores la on la.QuestionId = q.QuestionId
    left join TopVoters tv on tv.PostId = q.QuestionId
    left join PostActivityChanges pac on pac.PostId = q.QuestionId
),
RankedQuestions as (
    select
        qwa.*,
        row_number() over (
            partition by coalesce(array_length(string_to_array(substring(qwa.Tags FROM 2 FOR length(qwa.Tags) - 2), '><'), 1),0)
            order by qwa.Score desc, qwa.ViewCount desc, qwa.AnswerCount desc
        ) as TagRank
    from QuestionWithActivities qwa
),
DuplicatedPosts as (
    select
        pl.PostId,
        count(pl.Id) as DuplicateCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    group by pl.PostId
),
OwnerDetails as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        coalesce(ubc.GoldBadges,0) as GoldBadges,
        coalesce(ubc.SilverBadges,0) as SilverBadges,
        coalesce(ubc.BronzeBadges,0) as BronzeBadges
    from Users u
    left join UserBadgeCounts ubc on ubc.UserId = u.Id
),
FinalJoin as (
    select
        rq.QuestionId,
        rq.Title,
        rq.OwnerUserId,
        rq.Score,
        rq.ViewCount,
        rq.AnswerCount,
        rq.FavoriteCount,
        rq.TagCount,
        rq.Tags,
        rq.AvgAnswerScore,
        rq.MaxAnswerScore,
        rq.TotalVotes,
        rq.UpVotes,
        rq.DownVotes,
        rq.LastActivityChange,
        rq.EditCount,
        rq.HasClosureOrDeletion,
        rq.HistoryTypesInvolved,
        rq.TagRank,
        dd.DuplicateCount,
        od.Reputation,
        od.GoldBadges,
        od.SilverBadges,
        od.BronzeBadges,
        rq.CreationDate
    from RankedQuestions rq
    left join DuplicatedPosts dd on dd.PostId = rq.QuestionId
    left join OwnerDetails od on od.UserId = rq.OwnerUserId
    where rq.TagRank <= 3
)
select
    fj.QuestionId,
    fj.Title,
    substring(fj.Title FROM 1 FOR 50) || case when length(fj.Title) > 50 then '...' else '' end as ShortTitlePreview,
    fj.OwnerUserId,
    fj.Reputation as OwnerReputation,
    fj.GoldBadges,
    fj.SilverBadges,
    fj.BronzeBadges,
    fj.Score,
    fj.ViewCount,
    fj.AnswerCount,
    fj.FavoriteCount,
    fj.TagCount,
    fj.Tags,
    fj.AvgAnswerScore,
    fj.MaxAnswerScore,
    fj.TotalVotes,
    fj.UpVotes,
    fj.DownVotes,
    fj.DuplicateCount,
    fj.LastActivityChange,
    fj.EditCount,
    fj.HasClosureOrDeletion,
    fj.HistoryTypesInvolved,
    fj.CreationDate,
    dense_rank() over (order by fj.Score desc NULLS LAST, fj.ViewCount desc NULLS LAST) as PopularityRank,
    array_to_string(array_agg(distinct upper(trim(tag)) ) FILTER (WHERE tag IS NOT NULL), ', ') as UpperTagList,
    case
        when fj.EditCount > 10 then 'Highly Edited'
        when fj.EditCount between 5 and 10 then 'Moderately Edited'
        when fj.EditCount between 1 and 4 then 'Lightly Edited'
        else 'Never Edited'
    end as EditIntensity,
    case 
        when fj.ViewCount > 10000 and fj.LastActivityChange < (TIMESTAMP '2024-10-01 12:34:56' - interval '180 days') then 'Stale Popular Question'
        when fj.ViewCount > 10000 and fj.LastActivityChange >= (TIMESTAMP '2024-10-01 12:34:56' - interval '180 days') then 'Active Popular Question'
        else 'Normal'
    end as ActivityStatus
from FinalJoin fj
left join lateral (
    select unnest(string_to_array(substring(fj.Tags FROM 2 FOR length(fj.Tags) - 2), '><')) as tag
) tag_table on true
group by
    fj.QuestionId,
    fj.Title,
    fj.OwnerUserId,
    fj.Reputation,
    fj.GoldBadges,
    fj.SilverBadges,
    fj.BronzeBadges,
    fj.Score,
    fj.ViewCount,
    fj.AnswerCount,
    fj.FavoriteCount,
    fj.TagCount,
    fj.Tags,
    fj.AvgAnswerScore,
    fj.MaxAnswerScore,
    fj.TotalVotes,
    fj.UpVotes,
    fj.DownVotes,
    fj.DuplicateCount,
    fj.LastActivityChange,
    fj.EditCount,
    fj.HasClosureOrDeletion,
    fj.HistoryTypesInvolved,
    fj.CreationDate,
    fj.TagRank
order by PopularityRank
limit 50;