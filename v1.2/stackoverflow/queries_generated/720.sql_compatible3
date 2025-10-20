with recursive RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(u.Location, 'Unknown') as Location,
        coalesce(u.WebsiteUrl, '') as WebsiteUrl,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        row_number() over (order by u.Reputation desc) as RankByReputation
    from Users u
    where u.Reputation > 1000

    union all

    select 
        u2.Id,
        u2.DisplayName,
        u2.Reputation,
        u2.CreationDate,
        u2.LastAccessDate,
        coalesce(u2.Location, 'Unknown'),
        coalesce(u2.WebsiteUrl, ''),
        u2.Views,
        u2.UpVotes,
        u2.DownVotes,
        rua.RankByReputation + 1
    from Users u2
    join RecursiveUserActivity rua on rua.UserId = u2.Id - 1
    where u2.Reputation > 1000 and rua.RankByReputation < 10
),
TopQuestions as (
    select 
        p.Id, 
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        p.AnswerCount,
        p.AcceptedAnswerId
    from Posts p
    where p.PostTypeId = 1 and p.Score > 5
),
QuestionAnswerStats as (
    select 
        q.Id as QuestionId,
        count(a.Id) as TotalAnswers,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) filter (where a.Score is not null) as AvgAnswerScore,
        sum(case when a.OwnerUserId in (select UserId from RecursiveUserActivity) then 1 else 0 end) as AnswersByTopUsers
    from TopQuestions q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    group by q.Id
),
UserBadgeCounts as (
    select 
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
QuestionCloseStats as (
    select 
        ph.PostId,
        count(case when ph.PostHistoryTypeId = 10 then 1 end) as CloseEvents,
        count(case when ph.PostHistoryTypeId = 11 then 1 end) as ReopenEvents,
        max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) as LastCloseDate,
        max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate end) as LastReopenDate
    from PostHistory ph
    where ph.PostHistoryTypeId in (10,11)
    group by ph.PostId
),
QuestionVotesAgg as (
    select 
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as FavoriteVotes
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
),
CombinedStats as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.Score,
        q.ViewCount,
        q.Tags,
        q.AnswerCount,
        qa.TotalAnswers,
        qa.MaxAnswerScore,
        qa.AvgAnswerScore,
        qa.AnswersByTopUsers,
        coalesce(uc.GoldBadges, 0) as OwnerGoldBadges,
        coalesce(uc.SilverBadges, 0) as OwnerSilverBadges,
        coalesce(uc.BronzeBadges, 0) as OwnerBronzeBadges,
        coalesce(uc.TotalBadges, 0) as OwnerTotalBadges,
        coalesce(qcs.CloseEvents, 0) as CloseEvents,
        coalesce(qcs.ReopenEvents, 0) as ReopenEvents,
        qcs.LastCloseDate,
        qcs.LastReopenDate,
        coalesce(qv.UpVotes, 0) as UpVotes,
        coalesce(qv.DownVotes, 0) as DownVotes,
        coalesce(qv.FavoriteVotes, 0) as FavoriteVotes,
        u.DisplayName as OwnerDisplayName,
        u.Reputation as OwnerReputation,
        u.Location as OwnerLocation,
        u.CreationDate as OwnerCreationDate,
        q.OwnerUserId
    from TopQuestions q
    left join QuestionAnswerStats qa on qa.QuestionId = q.Id
    left join UserBadgeCounts uc on uc.UserId = q.OwnerUserId
    left join QuestionCloseStats qcs on qcs.PostId = q.Id
    left join QuestionVotesAgg qv on qv.PostId = q.Id
    left join Users u on u.Id = q.OwnerUserId
    where q.Tags is not null
),
TagExplode as (
    select 
        cs.QuestionId,
        tag AS Tag,
        cs.QuestionId as cs_QuestionId,
        cs.Title,
        cs.Score,
        cs.ViewCount,
        cs.Tags as cs_Tags,
        cs.AnswerCount,
        cs.TotalAnswers,
        cs.MaxAnswerScore,
        cs.AvgAnswerScore,
        cs.AnswersByTopUsers,
        cs.OwnerGoldBadges,
        cs.OwnerSilverBadges,
        cs.OwnerBronzeBadges,
        cs.OwnerTotalBadges,
        cs.CloseEvents,
        cs.ReopenEvents,
        cs.LastCloseDate,
        cs.LastReopenDate,
        cs.UpVotes,
        cs.DownVotes,
        cs.FavoriteVotes,
        cs.OwnerDisplayName,
        cs.OwnerReputation,
        cs.OwnerLocation,
        cs.OwnerCreationDate,
        cs.OwnerUserId
    from CombinedStats cs,
    lateral (
      select unnest(string_to_array(substring(cs.Tags FROM 2 FOR char_length(cs.Tags) - 2), '><')) as tag
    ) t
),
TagRanked as (
    select 
        te.cs_QuestionId as QuestionId,
        te.Tag,
        te.Title,
        te.Score,
        te.ViewCount,
        te.cs_Tags as Tags,
        te.AnswerCount,
        te.TotalAnswers,
        te.MaxAnswerScore,
        te.AvgAnswerScore,
        te.AnswersByTopUsers,
        te.OwnerGoldBadges,
        te.OwnerSilverBadges,
        te.OwnerBronzeBadges,
        te.OwnerTotalBadges,
        te.CloseEvents,
        te.ReopenEvents,
        te.LastCloseDate,
        te.LastReopenDate,
        te.UpVotes,
        te.DownVotes,
        te.FavoriteVotes,
        te.OwnerDisplayName,
        te.OwnerReputation,
        te.OwnerLocation,
        te.OwnerCreationDate,
        te.OwnerUserId,
        row_number() over (partition by te.Tag order by te.Score desc, te.ViewCount desc, te.AnswerCount desc) as TagRank
    from TagExplode te
),
FinalSelection as (
    select 
        tr.QuestionId,
        tr.Title,
        tr.Score,
        tr.ViewCount,
        tr.AnswerCount,
        tr.TotalAnswers,
        tr.MaxAnswerScore,
        tr.AvgAnswerScore,
        tr.AnswersByTopUsers,
        tr.OwnerGoldBadges,
        tr.OwnerSilverBadges,
        tr.OwnerBronzeBadges,
        tr.OwnerTotalBadges,
        tr.CloseEvents,
        tr.ReopenEvents,
        tr.LastCloseDate,
        tr.LastReopenDate,
        tr.UpVotes,
        tr.DownVotes,
        tr.FavoriteVotes,
        tr.OwnerDisplayName,
        tr.OwnerReputation,
        tr.OwnerLocation,
        tr.OwnerCreationDate,
        tr.Tag,
        tr.TagRank,
        tr.OwnerUserId,
        rank() over (partition by tr.OwnerUserId order by tr.Score desc) as OwnerBestQuestionRank
    from TagRanked tr
    where tr.TagRank <= 3
)
select 
    fs.QuestionId,
    fs.Title,
    fs.Tag,
    fs.Score,
    fs.ViewCount,
    fs.AnswerCount,
    fs.TotalAnswers,
    fs.MaxAnswerScore,
    coalesce(round(cast(fs.AvgAnswerScore as numeric),2),0) as AvgAnswerScore,
    fs.AnswersByTopUsers,
    fs.OwnerGoldBadges,
    fs.OwnerSilverBadges,
    fs.OwnerBronzeBadges,
    fs.OwnerTotalBadges,
    fs.CloseEvents,
    fs.ReopenEvents,
    fs.LastCloseDate,
    fs.LastReopenDate,
    fs.UpVotes,
    fs.DownVotes,
    fs.FavoriteVotes,
    fs.OwnerDisplayName,
    fs.OwnerReputation,
    fs.OwnerLocation,
    fs.OwnerCreationDate,
    fs.OwnerBestQuestionRank,
    case 
        when fs.CloseEvents > fs.ReopenEvents then 'Likely Closed' 
        when fs.CloseEvents = 0 then 'Never Closed' 
        else 'Open' 
    end as PostStatus,
    case 
        when fs.OwnerReputation > 20000 then 'HighRepOwner'
        when fs.OwnerReputation between 5000 and 20000 then 'MidRepOwner'
        else 'LowRepOwner'
    end as OwnerReputationCategory,
    length(fs.Title) as TitleLength,
    position('sql' in lower(fs.Title)) > 0 as TitleContainsSQL,
    case when fs.LastCloseDate is not null then extract(epoch from (timestamp '2024-10-01 12:34:56' - fs.LastCloseDate)) / 86400 else null end as DaysSinceLastClose,
    case when fs.LastReopenDate is not null then extract(epoch from (timestamp '2024-10-01 12:34:56' - fs.LastReopenDate)) / 86400 else null end as DaysSinceLastReopen
from FinalSelection fs
order by fs.Tag, fs.TagRank, fs.Score desc
limit 100;