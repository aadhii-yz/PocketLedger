<script lang="ts" generics="T">
  interface Column {
    header: string;
    accessor?: keyof T | ((row: T) => any);
    className?: string;
  }

  interface Props {
    data: T[];
    columns: Column[];
    class?: string;
    cell?: import("svelte").Snippet<[T, Column]>;
  }

  let { data, columns, class: className = "", cell }: Props = $props();

  function renderValue(row: T, column: Column) {
    if (!column.accessor) return "";
    if (typeof column.accessor === "function") {
      return column.accessor(row);
    }
    return row[column.accessor as keyof T];
  }
</script>

<div class="overflow-x-auto {className}">
  <table class="w-full">
    <thead class="bg-muted border-b border-border">
      <tr>
        {#each columns as column}
          <th class="px-6 py-3 text-left">
            {column.header}
          </th>
        {/each}
      </tr>
    </thead>
    <tbody>
      {#each data as row}
        <tr class="border-b border-border hover:bg-muted/50 transition-colors">
          {#each columns as column}
            <td class="px-6 py-4 {column.className || ''}">
              {#if cell}
                {@render cell(row, column)}
              {:else}
                {renderValue(row, column)}
              {/if}
            </td>
          {/each}
        </tr>
      {/each}
    </tbody>
  </table>
  {#if data.length === 0}
    <div class="text-center py-12 text-muted-foreground">No data available</div>
  {/if}
</div>
