with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate as PostCreationDate,
        p.Score as PostScore,
        p.ViewCount,
        p.Title,
        p.Tags,
        coalesce(b.BadgeCount, 0) as BadgeCount,
        coalesce(v.UpVotes, 0) as TotalUpVotes,
        coalesce(v.DownVotes, 0) as TotalDownVotes,
        row_number() over (partition by u.Id order by p.Score desc nulls last) as PostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select UserId, count(*) as BadgeCount
        from Badges
        where Class = 1
        group by UserId
    ) b on b.UserId = u.Id
    left join (
        select PostId,
            sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Votes
        group by PostId
    ) v on v.PostId = p.Id
    where u.Reputation > 1000
),
FilteredUserPosts as (
    select *
    from RecursiveUserActivity
    where PostRank <= 5
),
PostLinkStats as (
    select
        pl.PostId,
        count(distinct case when lt.Name = 'Duplicate' then pl.RelatedPostId end) as DuplicateLinks,
        count(distinct case when lt.Name = 'Linked' then pl.RelatedPostId end) as LinkedPosts
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId
),
PostCommentsStats as (
    select
        c.PostId,
        count(*) as TotalComments,
        avg(c.Score) filter (where c.Score is not null) as AvgCommentScore,
        max(length(c.Text)) as MaxCommentLength
    from Comments c
    group by c.PostId
),
CloseReasonsCounts as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        count(*) as CloseCount
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id and pht.Name = 'Post Closed'
    left join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
    group by ph.PostId, crt.Name
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionsCount,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswersCount,
        max(p.Score) filter (where p.PostTypeId = 2) as MaxAnswerScore,
        max(p.Score) filter (where p.PostTypeId = 1) as MaxQuestionScore,
        sum(vt.UpVotes) as SumUpVotes,
        sum(vt.DownVotes) as SumDownVotes,
        coalesce(avg(p.Score), 0) as AveragePostScore,
        min(p.CreationDate) as FirstPostDate,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select PostId,
            sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Votes
        group by PostId
    ) vt on vt.PostId = p.Id
    group by u.Id, u.DisplayName
),
TopTagsByUser AS (
    select
        fup.UserId,
        tag as TagName,
        count(*) as TagUsageCount
    from FilteredUserPosts fup
    cross join lateral (
        -- split tags like '<tag1><tag2>' into rows by extracting between '<' and '>'
        select trim(tagsplit) as tag
        from (
            select regexp_split_to_table(
                regexp_replace(fup.Tags, '(^>|<>$)', '', 'g'),
                '><'
            ) as tagsplit
        ) s
    ) t
    where fup.Tags is not null
    group by fup.UserId, tag
),
TagRankedByUser AS (
    select
        tbu.UserId,
        tbu.TagName,
        tbu.TagUsageCount,
        rank() over (partition by tbu.UserId order by tbu.TagUsageCount desc) as TagRank
    from TopTagsByUser tbu
),
DominantTags as (
    select UserId, TagName, TagUsageCount
    from TagRankedByUser
    where TagRank <= 3
),
ComprehensiveUserOverview as (
    select
        uas.UserId,
        uas.DisplayName,
        uas.TotalPosts,
        uas.QuestionsCount,
        uas.AnswersCount,
        uas.MaxAnswerScore,
        uas.MaxQuestionScore,
        uas.SumUpVotes,
        uas.SumDownVotes,
        uas.AveragePostScore,
        uas.FirstPostDate,
        uas.LastPostDate,
        coalesce(string_agg(dt.TagName || ' (' || dt.TagUsageCount || ')', ', '), '') as TopTags,
        coalesce(sum(pls.DuplicateLinks), 0) as TotalDuplicateLinks,
        coalesce(sum(pls.LinkedPosts), 0) as TotalLinkedPosts,
        coalesce(sum(pcs.TotalComments), 0) as TotalCommentsReceived,
        coalesce(avg(pcs.AvgCommentScore), 0) as AverageCommentScore,
        coalesce(max(pcs.MaxCommentLength), 0) as MaxCommentLength
    from UserActivitySummary uas
    left join FilteredUserPosts fup on fup.UserId = uas.UserId
    left join PostLinkStats pls on pls.PostId = fup.PostId
    left join PostCommentsStats pcs on pcs.PostId = fup.PostId
    left join DominantTags dt on dt.UserId = uas.UserId
    group by
        uas.UserId, uas.DisplayName, uas.TotalPosts, uas.QuestionsCount, uas.AnswersCount,
        uas.MaxAnswerScore, uas.MaxQuestionScore, uas.SumUpVotes, uas.SumDownVotes,
        uas.AveragePostScore, uas.FirstPostDate, uas.LastPostDate
),
UsersWithCloseVotes as (
    select
        ph.UserId,
        count(distinct ph.PostId) as ClosedPostsCount,
        string_agg(distinct crt.Name, ', ') as CloseReasons
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id and pht.Name = 'Post Closed'
    left join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
    where ph.UserId is not null
    group by ph.UserId
)
select
    cuo.UserId,
    cuo.DisplayName,
    cuo.TotalPosts,
    cuo.QuestionsCount,
    cuo.AnswersCount,
    cuo.MaxAnswerScore,
    cuo.MaxQuestionScore,
    cuo.SumUpVotes,
    cuo.SumDownVotes,
    cuo.AveragePostScore,
    cuo.FirstPostDate,
    cuo.LastPostDate,
    cuo.TopTags,
    cuo.TotalDuplicateLinks,
    cuo.TotalLinkedPosts,
    cuo.TotalCommentsReceived,
    cuo.AverageCommentScore,
    cuo.MaxCommentLength,
    coalesce(uwc.ClosedPostsCount, 0) as ClosedPostsCount,
    coalesce(uwc.CloseReasons, 'None') as CloseReasons
from ComprehensiveUserOverview cuo
left join UsersWithCloseVotes uwc on uwc.UserId = cuo.UserId
where cuo.TotalPosts > 10
order by cuo.SumUpVotes desc, cuo.AveragePostScore desc
limit 100;